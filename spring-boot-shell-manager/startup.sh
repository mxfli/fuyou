#!/bin/bash
#
# 生产环境应用启动脚本 - 支持多实例部署
# 使用方法: ./startup.sh [start|stop|restart|status] [实例名]
#

# 获取应用根目录（脚本所在目录的上一级）
APP_HOME=$(cd "$(dirname "$0")"/.. && pwd)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 加载环境配置
SET_ENV_FILE="$SCRIPT_DIR/set-env.sh"
if [ -f "$SET_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$SET_ENV_FILE"
fi

# 补丁类路径，用于存放覆盖jar文件中需要打补丁的class
PATCH_CLASSPATH="$APP_HOME/patch_classpath"
# 应用名称和版本（可通过set-env.sh覆盖）
APP_NAME="${APP_NAME:-springboot-http-app}"
APP_VERSION="${APP_VERSION:-}"
SERVERS_CONFIG="${APP_HOME}/servers.properties"

# 配置缓存（避免重复解析）
_SERVERS_CONFIG_CACHE_TIMESTAMP=0
_SERVERS_CONFIG_CACHE_KEYS=()
_SERVERS_CONFIG_CACHE_DIRS=()

# JAR 类型检测缓存
_JAR_TYPE_CACHE=""
_JAR_MAIN_CLASS_CACHE=""
_JAR_FILE_CACHE=""
_JAR_FILE_MTIME_CACHE=""

# 应用JAR和主类将通过智能检测确定
APP_JAR=""
JAR_TYPE=""
MAIN_CLASS=""

# 脚本的参数
MAX_WAIT_TIME=60  # 最大等待时间60秒
CHECK_INTERVAL=2  # 每2秒检查一次

# 基础日志函数
log_info() {
    echo "=> $*"
}

log_warn() {
    echo "=> 警告: $*"
}

log_error() {
    echo "=> 错误: $*"
}

# 获取文件修改时间（兼容 macOS/Linux）
get_file_mtime() {
    local file="$1"
    if [ -f "$file" ]; then
        stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# 检测JAR文件和类型
detect_jar_file_and_type() {
    echo "=> 检测应用JAR文件..."
    
    # 如果APP_VERSION有值，则用减号拼接在APP_NAME之后
    local jar_name="$APP_NAME"
    if [ -n "$APP_VERSION" ]; then
        jar_name="${APP_NAME}-${APP_VERSION}"
    fi
    
    # 设置JAR文件路径
    APP_JAR="${APP_HOME}/${jar_name}.jar"
    
    # 检查JAR文件是否存在
    if [ ! -f "$APP_JAR" ]; then
        echo "=> 错误: 应用JAR文件不存在: $APP_JAR"
        echo "   期望的文件名: ${jar_name}.jar"
        return 1
    fi
    
    echo "=> 找到应用JAR: $APP_JAR"
    
    # 检测JAR类型
    detect_jar_type_and_main_class
    return $?
}

# 检测JAR类型并设置主类
detect_jar_type_and_main_class() {
    if [ ! -f "$APP_JAR" ]; then
        log_error "应用JAR文件不存在: $APP_JAR"
        return 1
    fi

    local current_mtime
    current_mtime=$(get_file_mtime "$APP_JAR")
    if [ -n "$_JAR_TYPE_CACHE" ] && [ "$APP_JAR" = "$_JAR_FILE_CACHE" ] && [ "$current_mtime" = "$_JAR_FILE_MTIME_CACHE" ]; then
        JAR_TYPE="$_JAR_TYPE_CACHE"
        MAIN_CLASS="$_JAR_MAIN_CLASS_CACHE"
        log_info "JAR 类型(缓存): $JAR_TYPE, 主类: $MAIN_CLASS"
        return 0
    fi
    
    # 检查是否为 Fat JAR（包含 BOOT-INF 目录）
    if jar tf "$APP_JAR" | grep -q "^BOOT-INF/"; then
        log_info "检测到 Fat JAR 模式"
        MAIN_CLASS="org.springframework.boot.loader.JarLauncher"
        JAR_TYPE="fat"
    else
        log_info "检测到 Thin JAR 模式"
        # Thin JAR 使用 -jar 启动，主类由 MANIFEST.MF 指定
        MAIN_CLASS="(由MANIFEST.MF指定)"
        JAR_TYPE="thin"
    fi

    # 更新缓存
    _JAR_TYPE_CACHE="$JAR_TYPE"
    _JAR_MAIN_CLASS_CACHE="$MAIN_CLASS"
    _JAR_FILE_CACHE="$APP_JAR"
    _JAR_FILE_MTIME_CACHE="$current_mtime"

    log_info "JAR 类型: $JAR_TYPE, 主类: $MAIN_CLASS"
    return 0
}

# 从实例目录名中提取端口号
extract_port_from_instance_dir() {
    local instance_dir="$1"
    
    # 匹配格式: instance-端口号 或 任意名称-端口号
    if [[ "$instance_dir" =~ -([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # 如果没有匹配到端口号，返回空
    echo ""
    return 1
}

# 统一的PID文件清理函数
cleanup_pid_file() {
    local instance_name="$1"
    local pid_file="$2"
    
    if [ -f "$pid_file" ]; then
        if rm -f "$pid_file"; then
            echo "=> 已清理PID文件: $pid_file"
        else
            echo "=> 警告: 无法删除PID文件: $pid_file"
        fi
    fi
}

# 优雅停止相关参数
GRACEFUL_SHUTDOWN_TIMEOUT=${GRACEFUL_SHUTDOWN_TIMEOUT:-30}  # 优雅停止等待时间（秒）
FORCE_KILL_TIMEOUT=${FORCE_KILL_TIMEOUT:-10}               # 强制终止等待时间（秒）
ENABLE_ACTUATOR_SHUTDOWN=${ENABLE_ACTUATOR_SHUTDOWN:-false} # 是否启用Actuator shutdown
ACTUATOR_SHUTDOWN_PORT=${ACTUATOR_SHUTDOWN_PORT:-8080}      # Actuator端口
ACTUATOR_SHUTDOWN_TIMEOUT=${ACTUATOR_SHUTDOWN_TIMEOUT:-5}   # Actuator shutdown超时时间（秒）

# 读取多实例配置（无副作用，保持文件顺序）
read_servers_ordered() {
    # 有序数组（与 servers.properties 行顺序一致）
    SERVER_KEYS=()
    SERVER_DIRS=()

    local current_mtime
    current_mtime=$(get_file_mtime "$SERVERS_CONFIG")

    # 如果缓存有效，直接使用缓存
    if [ "$current_mtime" -eq "$_SERVERS_CONFIG_CACHE_TIMESTAMP" ] && [ ${#_SERVERS_CONFIG_CACHE_KEYS[@]} -gt 0 ]; then
        SERVER_KEYS=("${_SERVERS_CONFIG_CACHE_KEYS[@]}")
        SERVER_DIRS=("${_SERVERS_CONFIG_CACHE_DIRS[@]}")
        return 0
    fi

    if [ -f "$SERVERS_CONFIG" ]; then
        while IFS='=' read -r key value; do
            # 跳过空行和注释
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            
            # 安全的去除前后空格，避免命令注入
            key="${key#"${key%%[![:space:]]*}"}"    # 去除前导空格
            key="${key%"${key##*[![:space:]]}"}"    # 去除尾随空格
            value="${value#"${value%%[![:space:]]*}"}"  # 去除前导空格
            value="${value%"${value##*[![:space:]]}"}"  # 去除尾随空格
            
            # 验证key的合法性（只允许字母数字和下划线）
            if [[ "$key" =~ ^[a-zA-Z0-9_]+$ ]]; then
                SERVER_KEYS+=("$key")
                SERVER_DIRS+=("$value")
            else
                echo "=> 警告: 跳过无效的实例名称: $key"
            fi
        done < "$SERVERS_CONFIG"
    fi

    # 若未配置，回退到单实例默认
    if [ ${#SERVER_KEYS[@]} -eq 0 ]; then
        SERVER_KEYS=("server")
        SERVER_DIRS=("")
    fi

    # 更新缓存
    _SERVERS_CONFIG_CACHE_TIMESTAMP="$current_mtime"
    _SERVERS_CONFIG_CACHE_KEYS=("${SERVER_KEYS[@]}")
    _SERVERS_CONFIG_CACHE_DIRS=("${SERVER_DIRS[@]}")
}

# 获取实例配置（通过有序解析，避免重复读取配置）
get_instance_config() {
    local instance_name="$1"

    # 读取有序服务器列表
    read_servers_ordered

    # 定位实例索引
    local idx=-1
    local i
    for i in "${!SERVER_KEYS[@]}"; do
        if [ "$instance_name" = "${SERVER_KEYS[$i]}" ]; then
            idx=$i
            break
        fi
    done

    # 不存在则返回失败
    if [ $idx -lt 0 ]; then
        return 1
    fi

    # 解析实例目录
    local instance_dir="${SERVER_DIRS[$idx]}"
    if [ -z "$instance_dir" ]; then
        APP_RUNTIME_HOME="$APP_HOME"
        INSTANCE_PORT=""
    else
        APP_RUNTIME_HOME="$APP_HOME/$instance_dir"
        # 从实例目录名中提取端口号
        INSTANCE_PORT=$(extract_port_from_instance_dir "$instance_dir")
        if [ -n "$INSTANCE_PORT" ]; then
            echo "=> 检测到实例端口: $INSTANCE_PORT"
        fi
    fi

    # 设置实例相关变量
    PID_FILE="${APP_RUNTIME_HOME}/.app.pid"
    LOG_DIR="${APP_RUNTIME_HOME}/logs"
    LOG_FILE="${LOG_DIR}/${APP_NAME}${APP_VERSION:+-${APP_VERSION}}.out"

    # 创建实例日志目录
    if ! mkdir -p "$LOG_DIR"; then
        echo "=> 错误: 无法创建日志目录: $LOG_DIR"
        return 1
    fi

    # 智能检测JAR文件和类型
    if ! detect_jar_file_and_type; then
        echo "=> 错误: JAR文件检测失败"
        return 1
    fi
    
    # 设置配置及JVM选项 - 增加错误检查
    if ! setup_config_opts; then
        echo "=> 错误: 配置选项设置失败"
        return 1
    fi
    
    if ! setup_loader_opts; then
        echo "=> 错误: Loader选项设置失败"
        return 1
    fi
    
    if ! setup_java_opts; then
        echo "=> 错误: Java 环境配置失败，无法继续"
        return 1
    fi

    return 0
}

# 设置配置选项
setup_config_opts() {
    local runtime_config="${APP_RUNTIME_HOME}/appconfig/"
    local app_config="${APP_HOME}/appconfig/"
    
    # 验证必要的变量是否已设置
    if [ -z "$APP_RUNTIME_HOME" ] || [ -z "$APP_HOME" ]; then
        echo "=> 错误: 应用路径变量未正确设置"
        return 1
    fi
    
    # 设置活动配置文件
    # 优先使用配置文件中的SPRING_PROFILES_ACTIVE，如果未设置则使用default
    ACTIVE_PROFILE="${SPRING_PROFILES_ACTIVE:-default}"
    echo "=> 使用Spring Profile: $ACTIVE_PROFILE"
    CONFIG_OPTS="-Dspring.profiles.active=${ACTIVE_PROFILE}"
    
    # 如果检测到端口号，自动设置服务端口
    if [ -n "$INSTANCE_PORT" ]; then
        CONFIG_OPTS="$CONFIG_OPTS -Dserver.port=${INSTANCE_PORT}"
        echo "=> 自动设置服务端口: $INSTANCE_PORT"
    fi
    
    if [ -d "$runtime_config" ]; then
        CONFIG_OPTS="$CONFIG_OPTS -Dspring.config.location=file:${runtime_config}"
        if [ -f "${runtime_config}logback-spring.xml" ]; then
            CONFIG_OPTS="$CONFIG_OPTS -Dlogging.config=${runtime_config}logback-spring.xml"
        elif [ -f "${app_config}logback-spring.xml" ]; then
            CONFIG_OPTS="$CONFIG_OPTS -Dlogging.config=${app_config}logback-spring.xml"
        fi
    elif [ -d "$app_config" ]; then
        CONFIG_OPTS="$CONFIG_OPTS -Dspring.config.location=file:${app_config}"
        if [ -f "${app_config}logback-spring.xml" ]; then
            CONFIG_OPTS="$CONFIG_OPTS -Dlogging.config=${app_config}logback-spring.xml"
        fi
    fi
    
    return 0
}

# 设置Loader选项（根据JAR类型）
setup_loader_opts() {
    # 验证必要的变量是否已设置
    if [ -z "$APP_JAR" ] || [ -z "$APP_HOME" ] || [ -z "$APP_RUNTIME_HOME" ]; then
        echo "=> 错误: 应用路径变量未正确设置"
        return 1
    fi
    
    # 确保JAR类型已检测
    if [ -z "$JAR_TYPE" ]; then
        echo "=> 错误: JAR类型未检测，请先调用 detect_jar_file_and_type"
        return 1
    fi
    
    # 根据JAR类型设置不同的选项
    if [ "$JAR_TYPE" = "fat" ]; then
        # Fat JAR: 使用 -Dloader.path 加载外部依赖
        LOADER_OPTS="-Dloader.path=${PATCH_CLASSPATH},${APP_RUNTIME_HOME}/config/,${APP_HOME}/config/,${APP_HOME}/lib/"
        echo "=> Fat JAR Loader路径: ${PATCH_CLASSPATH},${APP_RUNTIME_HOME}/config/,${APP_HOME}/config/,${APP_HOME}/lib/"
    else
        # Thin JAR: 不使用 -Dloader.path，依赖MANIFEST.MF中的Class-Path
        LOADER_OPTS=""
        echo "=> Thin JAR: 使用MANIFEST.MF中的Class-Path，无需额外loader.path"
    fi
    
    return 0
}

# JVM 版本检测（设置 JAVA_MAJOR_VERSION）
detect_java_major_version() {
    local java_bin
    local java_source
    
    # 优先使用 JAVA_HOME，并提供诊断信息
    if [ -n "$JAVA_HOME" ]; then
        if [ -x "$JAVA_HOME/bin/java" ]; then
            java_bin="$JAVA_HOME/bin/java"
            java_source="JAVA_HOME ($JAVA_HOME)"
            echo "=> 使用 JAVA_HOME 中的 Java: $JAVA_HOME"
        else
            echo "=> 警告: JAVA_HOME 已设置但 $JAVA_HOME/bin/java 不可执行"
            echo "=> 回退使用系统 PATH 中的 java"
            java_bin="java"
            java_source="系统 PATH"
        fi
    else
        echo "=> 提示: JAVA_HOME 未设置，使用系统 PATH 中的 java"
        java_bin="java"
        java_source="系统 PATH"
    fi
    
    # 检查 java 命令是否可用
    if ! command -v "$java_bin" >/dev/null 2>&1; then
        echo "=> 错误: 找不到 Java 可执行文件"
        echo "=> 建议: 设置 JAVA_HOME 环境变量或确保 java 在 PATH 中"
        return 1
    fi
    
    # 获取并显示 Java 版本信息
    local version_output
    version_output=$("$java_bin" -version 2>&1)
    local ver_str
    ver_str=$(echo "$version_output" | awk -F '"' '/version/ {print $2}')
    
    if [ -z "$ver_str" ]; then
        echo "=> 错误: 无法获取 Java 版本信息"
        echo "=> Java 输出: $version_output"
        return 1
    fi
    
    # 解析主版本号
    if [[ "$ver_str" =~ ^1\.([0-9]+)\. ]]; then
        JAVA_MAJOR_VERSION="${BASH_REMATCH[1]}"
    else
        JAVA_MAJOR_VERSION="${ver_str%%.*}"
    fi
    
    # 显示诊断信息
    echo "=> Java 版本检测结果:"
    echo "   - Java 路径: $java_bin"
    echo "   - Java 来源: $java_source"
    echo "   - 版本字符串: $ver_str"
    echo "   - 主版本号: $JAVA_MAJOR_VERSION"
    
    # 验证版本号是否为数字
    if ! [[ "$JAVA_MAJOR_VERSION" =~ ^[0-9]+$ ]]; then
        echo "=> 警告: 解析的主版本号不是数字: $JAVA_MAJOR_VERSION"
        return 1
    fi
    
    return 0
}

# 加载优雅停止配置（支持外置配置）
load_shutdown_config() {
    # 外置配置位置：与 startup.sh 位于相同目录
    local shutdown_cfg="$SCRIPT_DIR/shutdown-env.sh"
    if [ -f "$shutdown_cfg" ]; then
        echo "=> 加载优雅停止配置: $shutdown_cfg"
        # shellcheck disable=SC1090
        . "$shutdown_cfg"
    fi
    
    # 显示当前配置
    echo "=> 优雅停止配置:"
    echo "   - SIGTERM 等待时间: ${GRACEFUL_SHUTDOWN_TIMEOUT}秒"
    echo "   - SIGKILL 等待时间: ${FORCE_KILL_TIMEOUT}秒"
    echo "   - Actuator shutdown: $([ "$ENABLE_ACTUATOR_SHUTDOWN" = "true" ] && echo "启用" || echo "禁用")"
    if [ "$ENABLE_ACTUATOR_SHUTDOWN" = "true" ]; then
        echo "   - Actuator 端口: ${ACTUATOR_SHUTDOWN_PORT}"
        echo "   - Actuator 超时: ${ACTUATOR_SHUTDOWN_TIMEOUT}秒"
    fi
}

# 加载/覆盖 JVM 可调参数（支持外置配置）
load_jvm_tunables() {
    # 默认值（可被外部文件覆盖）
    JVM_XMS=${JVM_XMS:-2g}
    JVM_XMX=${JVM_XMX:-4g}
    JVM_METASPACE_SIZE=${JVM_METASPACE_SIZE:-128m}
    JVM_MAX_METASPACE_SIZE=${JVM_MAX_METASPACE_SIZE:-512m}
    # JDK 8 PermGen 参数（仅 JDK 8 使用）
    JVM_PERM_SIZE=${JVM_PERM_SIZE:-256m}
    JVM_MAX_PERM_SIZE=${JVM_MAX_PERM_SIZE:-512m}
    JVM_MAX_GC_PAUSE_MS=${JVM_MAX_GC_PAUSE_MS:-200}
    JVM_IHOP=${JVM_IHOP:-45}
    JVM_GC_LOG_FILESIZE=${JVM_GC_LOG_FILESIZE:-20M}
    JVM_GC_LOG_FILECOUNT=${JVM_GC_LOG_FILECOUNT:-5}
    JVM_THREAD_STACK_SIZE=${JVM_THREAD_STACK_SIZE:-}
    JVM_HEAP_DUMP_PATH=${JVM_HEAP_DUMP_PATH:-${LOG_DIR}/heapdump.hprof}
    JVM_ERROR_FILE=${JVM_ERROR_FILE:-${LOG_DIR}/hs_err_pid%p.log}
    EXTRA_JAVA_OPTS=${EXTRA_JAVA_OPTS:-}
    
    # 注意：MAIN_CLASS 已在脚本开头设置，此处不再重复设置

    # 外置配置位置：与 startup.sh 位于相同目录
    local start_cfg="$SCRIPT_DIR/jvm-env.sh"
    if [ -f "$start_cfg" ]; then
        echo "=> 加载JVM配置: $start_cfg"
        # shellcheck disable=SC1090
        . "$start_cfg"
    fi
}

# 构建不同 JDK 版本的推荐 JVM 参数
build_java_opts_for_version() {
    log_info "开始 Java 环境检测..."
    
    if ! detect_java_major_version; then
        log_error "Java 版本检测失败，无法继续启动"
        return 1
    fi
    
    load_jvm_tunables

    # 构建公共 JVM 参数
    local COMMON_OPTS=""
    COMMON_OPTS="$COMMON_OPTS -server"
    COMMON_OPTS="$COMMON_OPTS -Xms${JVM_XMS} -Xmx${JVM_XMX}"
    COMMON_OPTS="$COMMON_OPTS -XX:MetaspaceSize=${JVM_METASPACE_SIZE} -XX:MaxMetaspaceSize=${JVM_MAX_METASPACE_SIZE}"
    COMMON_OPTS="$COMMON_OPTS -XX:+UseG1GC -XX:MaxGCPauseMillis=${JVM_MAX_GC_PAUSE_MS} -XX:InitiatingHeapOccupancyPercent=${JVM_IHOP}"
    COMMON_OPTS="$COMMON_OPTS -XX:+ParallelRefProcEnabled -XX:+UseStringDeduplication"
    COMMON_OPTS="$COMMON_OPTS -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JVM_HEAP_DUMP_PATH} -XX:ErrorFile=${JVM_ERROR_FILE}"
    if [ -n "$JVM_THREAD_STACK_SIZE" ]; then
        COMMON_OPTS="$COMMON_OPTS -Xss${JVM_THREAD_STACK_SIZE}"
    fi

    # 各版本按需构建参数
    case "$JAVA_MAJOR_VERSION" in
        8)
            # JDK 8: 使用 Metaspace（PermGen 在 JDK 8 中已移除）+ 旧式 GC 日志
            JAVA_VERSION_OPTS="$COMMON_OPTS -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:${LOG_DIR}/gc.log"
            JAVA_VERSION_OPTS="$JAVA_VERSION_OPTS -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=${JVM_GC_LOG_FILECOUNT} -XX:GCLogFileSize=${JVM_GC_LOG_FILESIZE}"
            ;;
        11|17|21|25)
            # JDK 11/17/21/25: 使用 Metaspace + 新式 -Xlog GC 日志
            JAVA_VERSION_OPTS="$COMMON_OPTS -Xlog:gc*,safepoint:file=${LOG_DIR}/gc.log:time,level,tags:filecount=${JVM_GC_LOG_FILECOUNT},filesize=${JVM_GC_LOG_FILESIZE}"
            ;;
        *)
            # 兜底：JDK 9/10 或未识别版本，使用现代参数集
            JAVA_VERSION_OPTS="$COMMON_OPTS -Xlog:gc*,safepoint:file=${LOG_DIR}/gc.log:time,level,tags:filecount=${JVM_GC_LOG_FILECOUNT},filesize=${JVM_GC_LOG_FILESIZE}"
            ;;
    esac

    # 系统/应用级通用 -D
    local SYS_PROPS="-Djson.defaultWriterFeatures=LargeObject -DLOG_HOME=${LOG_DIR} -Dlogging.file.path=${LOG_DIR} -Duser.dir=${APP_RUNTIME_HOME}"

    # 允许追加自定义参数
    if [ -n "$EXTRA_JAVA_OPTS" ]; then
        JAVA_OPTS="$JAVA_VERSION_OPTS $SYS_PROPS $EXTRA_JAVA_OPTS"
    else
        JAVA_OPTS="$JAVA_VERSION_OPTS $SYS_PROPS"
    fi
}

# 设置JVM参数（在获取实例配置后调用）
setup_java_opts() {
    if ! build_java_opts_for_version; then
        echo "=> 错误: JVM 参数构建失败"
        return 1
    fi
}

# 检查应用是否运行
check_pid() {
    if [ ! -f "$PID_FILE" ]; then
        echo ""
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)

    if [ -z "$pid" ]; then
        rm -f "$PID_FILE"
        echo ""
        return 1
    fi

    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        log_warn "PID文件包含无效内容: $pid"
        rm -f "$PID_FILE"
        echo ""
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        local cmdline
        cmdline=$(ps -p "$pid" -o command= 2>/dev/null)
        if [ -n "$APP_JAR" ] && [[ "$cmdline" =~ java.*"$APP_JAR" ]]; then
            echo "$pid"
            return 0
        fi
        if [ -z "$APP_JAR" ] && [[ "$cmdline" =~ java ]]; then
            echo "$pid"
            return 0
        fi
        log_warn "PID $pid 不是预期的 Java 进程"
        rm -f "$PID_FILE"
        echo ""
        return 1
    fi

    rm -f "$PID_FILE"
    echo ""
    return 1
}

# 检查Spring Boot应用启动状态
check_spring_boot_startup() {
    local instance_name="$1"
    local java_pid="$2"
    local max_wait_time=$MAX_WAIT_TIME  # 最大等待时间60秒
    local check_interval=$CHECK_INTERVAL  # 每2秒检查一次
    local waited_time=0
    
    echo "=> 等待Spring Boot应用启动完成..."
    
    while [ $waited_time -lt $max_wait_time ]; do
        # 首先检查进程是否还存在
        if ! kill -0 "$java_pid" 2>/dev/null; then
            echo "=> 警告: 进程 $java_pid 已停止"
            cleanup_pid_file "$instance_name" "$PID_FILE"
            return 1
        fi
        
        # 检查日志文件是否存在
        if [ -f "$LOG_FILE" ]; then
            # 检查是否有启动成功的标识
            if grep -q "Started.*in.*seconds" "$LOG_FILE" 2>/dev/null; then
                echo "=> Spring Boot应用启动成功! (用时: ${waited_time}秒)"
                return 0
            fi
            
            # 检查是否有应用关闭的标识
            if grep -qE "(Stopping|Shutdown|Application shutdown|Shutting down|stopped in|Closing)" "$LOG_FILE" 2>/dev/null; then
                echo "=> 警告: 检测到应用关闭信号，启动失败"
                cleanup_pid_file "$instance_name" "$PID_FILE"
                return 1
            fi
            
            # 检查是否有严重错误
            if grep -qE "(Exception|Error.*startup|Failed to start|Unable to start|startup failed)" "$LOG_FILE" 2>/dev/null; then
                echo "=> 警告: 检测到启动错误"
                cleanup_pid_file "$instance_name" "$PID_FILE"
                return 1
            fi
        fi
        
        sleep $check_interval
        waited_time=$((waited_time + check_interval))
        echo "=> 等待中... (${waited_time}/${max_wait_time}秒)"
    done
    
    # 超时检查
    echo "=> 警告: 等待${max_wait_time}秒后仍未检测到启动完成标识"
    echo "=> 进程状态检查..."
    
    if kill -0 "$java_pid" 2>/dev/null; then
        echo "=> 警告: 进程仍在运行但未检测到启动完成，可能启动异常"
        echo "=> 建议检查日志: $LOG_FILE 和 $LOG_DIR"
        return 1
    else
        echo "=> 警告: 进程已停止，启动失败"
        return 1
    fi
}

# 构建 Java 启动命令数组（避免参数解析问题）
build_java_cmd_array() {
    JAVA_CMD=("java")

    if [ -n "$JAVA_OPTS" ]; then
        read -ra _java_opts <<< "$JAVA_OPTS"
        JAVA_CMD+=("${_java_opts[@]}")
    fi

    if [ -n "$CONFIG_OPTS" ]; then
        read -ra _config_opts <<< "$CONFIG_OPTS"
        JAVA_CMD+=("${_config_opts[@]}")
    fi

    if [ -n "$LOADER_OPTS" ]; then
        read -ra _loader_opts <<< "$LOADER_OPTS"
        JAVA_CMD+=("${_loader_opts[@]}")
    fi

    JAVA_CMD+=("-jar" "$APP_JAR")
}

# 启动单个应用实例
start() {
    local instance_name="$1"
    
    if ! get_instance_config "$instance_name"; then
        echo "=> 错误: 实例 '$instance_name' 不存在"
        return 1
    fi
    
    pid=$(check_pid)
    if [ -n "$pid" ]; then
        echo "=> $APP_NAME 实例 '$instance_name' 已在运行中! (pid: $pid)"
        return 0
    fi

    echo "=> 正在启动 $APP_NAME 实例 '$instance_name'..."
    echo "=> 运行目录: $APP_RUNTIME_HOME"
    echo "=> 日志目录: $LOG_DIR"
    echo "=> 控制台日志: $LOG_FILE"
    
    # 清空或创建日志文件，确保检查的是当前启动的日志
    > "$LOG_FILE"
    
    # 根据JAR类型构建启动命令
    # 统一使用 -jar 启动方式（适用于Fat JAR和Thin JAR）
    echo "=> 启动方式: JAR 模式 (-jar)"
    echo "=> JAR文件: $APP_JAR"
    echo "=> JAR类型: $JAR_TYPE"
    echo "=> 启动命令预览:"
    build_java_cmd_array
    printf "   %s " "${JAVA_CMD[@]}"
    echo ""
    echo ""
    
    # 统一的JAR启动命令
    nohup "${JAVA_CMD[@]}" >> "$LOG_FILE" 2>&1 &
    local java_pid=$!
    echo $java_pid > "$PID_FILE"
    
    # 基础进程检查
    sleep 2
    if ! kill -0 "$java_pid" 2>/dev/null; then
        echo "=> $APP_NAME 实例 '$instance_name' 进程启动失败"
        cleanup_pid_file "$instance_name" "$PID_FILE"
        echo "=> 请检查日志: $LOG_FILE"
        return 1
    fi
    
    # Spring Boot启动状态检查
    if check_spring_boot_startup "$instance_name" "$java_pid"; then
        echo "=> $APP_NAME 实例 '$instance_name' 启动成功! (pid: $java_pid)"
        echo "=> 控制台日志输出到: $LOG_FILE"
        echo "=> 应用日志输出到: $LOG_DIR"
        return 0
    else
        echo "=> $APP_NAME 实例 '$instance_name' 启动失败"
        echo "=> 请检查日志: $LOG_FILE 和 $LOG_DIR"
        # PID文件已在check_spring_boot_startup中清理
        return 1
    fi
}

# 启动所有实例（按配置文件顺序）
start_all() {
    read_servers_ordered
    local success_count=0
    local total_count=${#SERVER_KEYS[@]}

    echo "=> 开始启动所有实例..."
    echo "=> 发现 ${#SERVER_KEYS[@]} 个实例"
    echo ""

    local idx=0
    for instance_name in "${SERVER_KEYS[@]}"; do
        idx=$((idx + 1))
        echo "[$idx/${#SERVER_KEYS[@]}] 启动实例: $instance_name"

        # 在子shell中启动实例，避免变量污染和PID混乱
        (
            if start "$instance_name"; then
                exit 0
            else
                exit 1
            fi
        )

        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
            echo "✓ 实例 '$instance_name' 启动成功"
        else
            echo "✗ 实例 '$instance_name' 启动失败"
        fi
        echo ""

        # 实例间启动间隔，避免资源竞争
        if [ $idx -lt ${#SERVER_KEYS[@]} ]; then
            sleep 3
        fi
    done

    echo "=> 启动完成: $success_count/$total_count 个实例启动成功"

    if [ $success_count -eq $total_count ]; then
        echo "=> 所有实例启动成功!"
        return 0
    else
        echo "=> 部分实例启动失败，请检查日志"
        return 1
    fi
}

# 尝试通过Spring Boot Actuator shutdown端点优雅关闭应用
try_actuator_shutdown() {
    local instance_name="$1"
    local pid="$2"
    
    if [ "$ENABLE_ACTUATOR_SHUTDOWN" != "true" ]; then
        return 1  # 未启用Actuator shutdown
    fi
    
    # 检查curl是否可用
    if ! command -v curl >/dev/null 2>&1; then
        echo "   - 警告: curl 不可用，跳过 Actuator shutdown"
        return 1
    fi
    
    echo "   - 尝试通过 Actuator shutdown 端点优雅关闭..."
    
    # 尝试调用shutdown端点
    local shutdown_url="http://localhost:${ACTUATOR_SHUTDOWN_PORT}/actuator/shutdown"
    local response
    
    if response=$(curl -s -X POST "$shutdown_url" -H "Content-Type: application/json" --connect-timeout "$ACTUATOR_SHUTDOWN_TIMEOUT" 2>/dev/null); then
        echo "   - Actuator shutdown 请求已发送: $response"
        
        # 等待应用响应shutdown请求
        local wait_count=0
        while [ $wait_count -lt "$ACTUATOR_SHUTDOWN_TIMEOUT" ]; do
            if ! kill -0 "$pid" 2>/dev/null; then
                echo "   - 应用已通过 Actuator shutdown 优雅关闭"
                return 0
            fi
            sleep 1
            wait_count=$((wait_count + 1))
        done
        
        echo "   - Actuator shutdown 超时，继续使用信号方式"
    else
        echo "   - Actuator shutdown 请求失败，继续使用信号方式"
    fi
    
    return 1
}

# 等待进程终止（带超时）
wait_for_process_termination() {
    local pid="$1"
    local timeout="$2"
    local signal_name="$3"
    
    local wait_count=0
    while [ $wait_count -lt "$timeout" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "   - 进程已响应 $signal_name 信号并终止 (等待时间: ${wait_count}秒)"
            return 0
        fi
        sleep 1
        wait_count=$((wait_count + 1))
        
        # 每5秒显示一次等待状态
        if [ $((wait_count % 5)) -eq 0 ]; then
            echo "   - 等待进程响应 $signal_name 信号... (${wait_count}/${timeout}秒)"
        fi
    done
    
    echo "   - 等待 $signal_name 信号超时 (${timeout}秒)"
    return 1
}

# 停止单个应用实例
stop() {
    local instance_name="$1"
    
    if ! get_instance_config "$instance_name"; then
        echo "=> 错误: 实例 '$instance_name' 不存在"
        return 1
    fi
    
    # 加载优雅停止配置
    load_shutdown_config
    
    pid=$(check_pid)
    if [ -z "$pid" ]; then
        echo "=> $APP_NAME 实例 '$instance_name' 未运行"
        return 0
    fi
    
    echo "=> 正在优雅停止 $APP_NAME 实例 '$instance_name' (pid: $pid)..."
    echo "=> 停止策略: Actuator shutdown → SIGTERM → SIGINT → SIGKILL"
    
    # 第一步: 尝试通过 Actuator shutdown 端点优雅关闭
    if try_actuator_shutdown "$instance_name" "$pid"; then
        cleanup_pid_file "$instance_name" "$PID_FILE"
        echo "=> $APP_NAME 实例 '$instance_name' 已通过 Actuator 优雅停止"
        return 0
    fi
    
    # 第二步: 发送 SIGTERM 信号进行优雅关闭
    echo "=> 发送 SIGTERM 信号进行优雅关闭..."
    if kill -TERM "$pid" 2>/dev/null; then
        if wait_for_process_termination "$pid" "$GRACEFUL_SHUTDOWN_TIMEOUT" "SIGTERM"; then
            cleanup_pid_file "$instance_name" "$PID_FILE"
            echo "=> $APP_NAME 实例 '$instance_name' 已优雅停止"
            return 0
        fi
    else
        echo "   - 发送 SIGTERM 信号失败"
    fi
    
    # 第三步: 发送 SIGINT 信号（Ctrl+C）
    echo "=> 发送 SIGINT 信号..."
    if kill -INT "$pid" 2>/dev/null; then
        if wait_for_process_termination "$pid" "$FORCE_KILL_TIMEOUT" "SIGINT"; then
            cleanup_pid_file "$instance_name" "$PID_FILE"
            echo "=> $APP_NAME 实例 '$instance_name' 已停止"
            return 0
        fi
    else
        echo "   - 发送 SIGINT 信号失败"
    fi
    
    # 第四步: 使用 SIGKILL 强制终止
    echo "=> 优雅关闭失败，使用 SIGKILL 强制终止..."
    if kill -KILL "$pid" 2>/dev/null; then
        # SIGKILL 无法被忽略，但仍需等待系统清理
        sleep 2
        if ! kill -0 "$pid" 2>/dev/null; then
            cleanup_pid_file "$instance_name" "$PID_FILE"
            echo "=> $APP_NAME 实例 '$instance_name' 已被强制停止"
            return 0
        else
            echo "=> 警告: 进程 $pid 可能处于不可中断状态"
            cleanup_pid_file "$instance_name" "$PID_FILE"
            return 1
        fi
    else
        echo "=> 错误: 无法终止进程 $pid"
        return 1
    fi
}

# 停止所有实例（按配置文件顺序）
stop_all() {
    read_servers_ordered
    local success_count=0
    local total_count=${#SERVER_KEYS[@]}

    echo "=> 开始停止所有实例..."
    echo "=> 发现 ${#SERVER_KEYS[@]} 个实例"
    echo ""

    local idx=0
    for instance_name in "${SERVER_KEYS[@]}"; do
        idx=$((idx + 1))
        echo "[$idx/${#SERVER_KEYS[@]}] 停止实例: $instance_name"

        # 在子shell中停止实例，避免变量污染
        (
            if stop "$instance_name"; then
                exit 0
            else
                exit 1
            fi
        )

        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
            echo "✓ 实例 '$instance_name' 停止成功"
        else
            echo "✗ 实例 '$instance_name' 停止失败"
        fi
        echo ""
    done

    echo "=> 停止完成: $success_count/$total_count 个实例停止成功"

    if [ $success_count -eq $total_count ]; then
        echo "=> 所有实例停止成功!"
        return 0
    else
        echo "=> 部分实例停止失败"
        return 1
    fi
}

# 重启单个应用实例
restart() {
    local instance_name="$1"
    stop "$instance_name"
    sleep 2
    start "$instance_name"
}

# 滚动重启所有实例（保障业务连续性，按配置文件顺序）
restart_all() {
    read_servers_ordered
    local success_count=0
    local total_count=${#SERVER_KEYS[@]}

    echo "=> 开始滚动重启所有实例（保障业务连续性）..."
    echo "=> 发现 ${#SERVER_KEYS[@]} 个实例"
    echo "=> 策略：逐个重启，如有失败则停止后续重启"
    echo ""

    local idx=0
    for instance_name in "${SERVER_KEYS[@]}"; do
        idx=$((idx + 1))
        echo "[$idx/${#SERVER_KEYS[@]}] 滚动重启实例: $instance_name"
        echo ""

        # 在子shell中重启实例，避免变量污染
        (
            echo "  => 步骤1: 停止实例 $instance_name"
            if stop "$instance_name"; then
                echo "  => 步骤2: 等待 3 秒后启动实例 $instance_name"
                sleep 3
                if start "$instance_name"; then
                    echo "  => 实例 $instance_name 重启成功"
                    exit 0
                else
                    echo "  => 实例 $instance_name 启动失败"
                    exit 1
                fi
            else
                echo "  => 实例 $instance_name 停止失败"
                exit 1
            fi
        )

        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
            echo "✓ 实例 '$instance_name' 滚动重启成功"

            # 重启成功后等待一段时间，确保服务稳定后再重启下一个
            if [ $idx -lt ${#SERVER_KEYS[@]} ]; then
                echo "  => 等待 10 秒确保服务稳定，然后重启下一个实例..."
                sleep 10
            fi
        else
            echo "✗ 实例 '$instance_name' 滚动重启失败"
            echo ""
            echo "⚠️  警告: 检测到重启失败，为保障业务连续性，立即终止滚动重启过程"
            echo "=> 已成功重启: $success_count 个实例"
            echo "=> 失败位置: 第 $idx 个实例 ($instance_name)"
            echo "=> 剩余未重启: $((${#SERVER_KEYS[@]} - idx)) 个实例"
            echo ""
            echo "🛡️  保护措施: 保持其他正在运行的实例不受影响"
            echo "📋 建议操作:"
            echo "   1. 检查失败实例的日志文件"
            echo "   2. 修复启动问题"
            echo "   3. 手动重启失败的实例: $0 restart $instance_name"
            echo "   4. 确认修复后，可继续重启剩余实例"
            echo ""
            echo "📁 关键日志位置:"
            if get_instance_config "$instance_name"; then
                echo "   - 控制台日志: $LOG_FILE"
                echo "   - 应用日志: $LOG_DIR"
            fi
            return 1
        fi
        echo ""
    done

    echo "=> 滚动重启完成: $success_count/$total_count 个实例重启成功"

    if [ $success_count -eq $total_count ]; then
        echo "=> 所有实例滚动重启成功! 业务连续性得到保障"
        return 0
    else
        echo "=> 部分实例重启失败"
        return 1
    fi
}

# 检查应用状态
status() {
    local instance_name="$1"
    
    if ! get_instance_config "$instance_name"; then
        echo "=> 错误: 实例 '$instance_name' 不存在"
        return 1
    fi
    
    pid=$(check_pid)
    if [ -n "$pid" ]; then
        echo "=> $APP_NAME 实例 '$instance_name' 正在运行 (pid: $pid)"
        echo "=> 运行目录: $APP_RUNTIME_HOME"
        echo "=> 进程信息:"
        ps -f -p $pid
        echo "=> 控制台日志文件: $LOG_FILE"
        echo "=> 应用日志目录: $LOG_DIR"
    else
        echo "=> $APP_NAME 实例 '$instance_name' 未运行"
    fi
}

# 显示可用实例列表（与配置文件顺序一致）
show_instances() {
    echo "可用的实例:"
    read_servers_ordered
    for i in "${!SERVER_KEYS[@]}"; do
        local key="${SERVER_KEYS[$i]}"
        local dir="${SERVER_DIRS[$i]}"
        local display_dir
        if [ -z "$dir" ]; then
            display_dir="$APP_HOME (默认)"
        else
            display_dir="$APP_HOME/$dir"
        fi
        echo "$((i+1)). $key -> $display_dir"
    done
}

# 显示命令菜单
show_command_menu() {
    echo "请选择操作："
    echo "1. start   - 启动应用"
    echo "2. stop    - 停止应用"
    echo "3. restart - 重启应用"
    echo "4. status  - 查看状态"
    echo ""
    echo "请输入命令名称或对应数字 (start/stop/restart/status 或 1/2/3/4):"
}

# 验证命令输入
validate_command() {
    local input="$1"
    case "$input" in
        start|1)
            echo "start"
            return 0
            ;;
        stop|2)
            echo "stop"
            return 0
            ;;
        restart|3)
            echo "restart"
            return 0
            ;;
        status|4)
            echo "status"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 获取实例选择（保持与配置文件顺序一致）
get_instance_choice() {
    read_servers_ordered

    # 如果只有一个实例，直接返回
    if [ ${#SERVER_KEYS[@]} -eq 1 ]; then
        echo "${SERVER_KEYS[0]}"
        return 0
    fi

    # 显示实例选择菜单
    echo ""
    echo "请选择要操作的实例:"
    show_instances
    echo ""
    echo "请输入实例名称或对应数字:"

    while true; do
        read -r user_input

        if [ -z "$user_input" ]; then
            echo "输入不能为空，请重新选择。"
            continue
        fi

        # 数字选择
        if [[ "$user_input" =~ ^[0-9]+$ ]]; then
            local index=$((user_input - 1))
            if [ $index -ge 0 ] && [ $index -lt ${#SERVER_KEYS[@]} ]; then
                echo "${SERVER_KEYS[$index]}"
                return 0
            else
                echo "数字选择超出范围，请重新选择。"
                continue
            fi
        fi

        # 名称选择
        for i in "${!SERVER_KEYS[@]}"; do
            if [ "$user_input" = "${SERVER_KEYS[$i]}" ]; then
                echo "$user_input"
                return 0
            fi
        done

        echo "实例 '$user_input' 不存在，请重新选择。"
    done
}

# 检查所有实例状态（按配置文件顺序）
status_all() {
    read_servers_ordered
    local running_count=0
    local total_count=${#SERVER_KEYS[@]}

    echo "=> 检查所有实例状态..."
    echo "=> 发现 ${#SERVER_KEYS[@]} 个实例"
    echo ""

    local idx=0
    for instance_name in "${SERVER_KEYS[@]}"; do
        idx=$((idx + 1))
        echo "[$idx/${#SERVER_KEYS[@]}] 实例: $instance_name"

        # 在子shell中检查状态，避免变量污染
        (
            if get_instance_config "$instance_name"; then
                pid=$(check_pid)
                if [ -n "$pid" ]; then
                    echo "  状态: 运行中 (pid: $pid)"
                    echo "  目录: $APP_RUNTIME_HOME"
                    exit 0
                else
                    echo "  状态: 未运行"
                    exit 1
                fi
            else
                echo "  状态: 配置错误"
                exit 1
            fi
        )

        if [ $? -eq 0 ]; then
            running_count=$((running_count + 1))
            echo "  ✓ 正常运行"
        else
            echo "  ✗ 未运行"
        fi
        echo ""
    done

    echo "=> 状态汇总: $running_count/$total_count 个实例正在运行"

    if [ $running_count -eq $total_count ]; then
        echo "=> 所有实例都在运行!"
        return 0
    elif [ $running_count -eq 0 ]; then
        echo "=> 所有实例都未运行"
        return 1
    else
        echo "=> 部分实例在运行"
        return 1
    fi
}

# 执行对应的操作
execute_command() {
    local cmd="$1"
    local instance="$2"
    
    # 检查是否是 all 操作
    if [ "$instance" = "all" ]; then
        case "$cmd" in
            start)
                start_all
                ;;
            stop)
                stop_all
                ;;
            restart)
                restart_all
                ;;
            status)
                status_all
                ;;
        esac
    else
        case "$cmd" in
            start)
                start "$instance"
                ;;
            stop)
                stop "$instance"
                ;;
            restart)
                restart "$instance"
                ;;
            status)
                status "$instance"
                ;;
        esac
    fi
}

# 主逻辑
main() {
    local command=""
    local instance=""
    
    # 处理命令参数
    if [ $# -eq 0 ]; then
        # 没有提供参数，显示命令菜单
        while true; do
            show_command_menu
            read -r user_input
            
            if [ -z "$user_input" ]; then
                echo "输入不能为空，请重新选择。"
                echo ""
                continue
            fi
            
            command=$(validate_command "$user_input")
            if [ $? -eq 0 ]; then
                break
            else
                echo "选择错误，请重新选择。"
                echo ""
            fi
        done
    elif [ $# -eq 1 ]; then
        # 只提供了命令参数
        command=$(validate_command "$1")
        if [ $? -ne 0 ]; then
            echo "错误: 无效的命令 '$1'"
            echo "用法: $0 {start|stop|restart|status} [实例名|all]"
            exit 1
        fi
    elif [ $# -eq 2 ]; then
        # 提供了命令和实例参数
        command=$(validate_command "$1")
        if [ $? -ne 0 ]; then
            echo "错误: 无效的命令 '$1'"
            echo "用法: $0 {start|stop|restart|status} [实例名|all]"
            exit 1
        fi
        instance="$2"
    else
        echo "用法: $0 {start|stop|restart|status} [实例名|all]"
        exit 1
    fi
    
    # 处理实例参数
    if [ -z "$instance" ]; then
        echo ""
        echo "请选择要操作的实例 (直接按回车默认选择 all - 所有实例):"
        
        # 检查是否存在servers.properties文件
        if [ -f "$SERVERS_CONFIG" ]; then
            # 显示实例选择菜单（保持与servers.properties的顺序一致）
            show_instances
            echo ""
            echo "输入选项:"
            echo "- 实例名称或对应数字"
            echo "- 'all' 或直接按回车 - 操作所有实例"
            echo ""
            echo "请输入选择:"
            
            read -r user_input

            # 读取配置（保持有序）
            read_servers_ordered

            # 如果用户直接按回车或输入 all，则操作所有实例
            if [ -z "$user_input" ] || [ "$user_input" = "all" ]; then
                instance="all"
            else
                # 数字选择
                if [[ "$user_input" =~ ^[0-9]+$ ]]; then
                    index=$((user_input - 1))
                    if [ $index -ge 0 ] && [ $index -lt ${#SERVER_KEYS[@]} ]; then
                        instance="${SERVER_KEYS[$index]}"
                    else
                        echo "数字选择超出范围，默认操作所有实例。"
                        instance="all"
                    fi
                else
                    # 名称选择
                    chosen=""
                    for i in "${!SERVER_KEYS[@]}"; do
                        if [ "$user_input" = "${SERVER_KEYS[$i]}" ]; then
                            chosen="${SERVER_KEYS[$i]}"
                            break
                        fi
                    done
                    if [ -n "$chosen" ]; then
                        instance="$chosen"
                    else
                        echo "实例 '$user_input' 不存在，默认操作所有实例。"
                        instance="all"
                    fi
                fi
            fi
        else
            # 没有配置文件，单实例运行
            echo "未找到 servers.properties 配置文件"
            echo "=> 单实例运行，直接开始执行第1步骤选择的操作"
            instance="server"
        fi
    fi
    
    echo ""
    if [ "$instance" = "all" ]; then
        echo "=> 即将执行命令: $command (所有实例)"
    else
        echo "=> 即将执行命令: $command (实例: $instance)"
    fi
    echo ""
    execute_command "$command" "$instance"
}

# 运行主函数
main "$@"
exit 0