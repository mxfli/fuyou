#!/bin/bash
#
# 生产环境应用启动脚本 - 支持多实例部署
# 使用方法: ./startup.sh [start|stop|restart|status] [实例名]
#

# 获取应用根目录（脚本所在目录的上一级）
APP_HOME=$(cd "$(dirname "$0")"/.. && pwd)

# 补丁类路径，用于存放覆盖jar文件中需要打补丁的class
PATCH_CLASSPATH="$APP_HOME/patch_classpath"
APP_NAME="nipis-gj-transfer-0.2.0-SNAPSHOT"
APP_JAR="${APP_HOME}/${APP_NAME}.jar"
SERVERS_CONFIG="${APP_HOME}/servers.properties"

# 读取多实例配置（无副作用，保持文件顺序）
read_servers_ordered() {
    # 有序数组（与 servers.properties 行顺序一致）
    SERVER_KEYS=()
    SERVER_DIRS=()

    if [ -f "$SERVERS_CONFIG" ]; then
        while IFS='=' read -r key value; do
            # 跳过空行和注释
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            # 去除前后空格
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            SERVER_KEYS+=("$key")
            SERVER_DIRS+=("$value")
        done < "$SERVERS_CONFIG"
    fi

    # 若未配置，回退到单实例默认
    if [ ${#SERVER_KEYS[@]} -eq 0 ]; then
        SERVER_KEYS=("server")
        SERVER_DIRS=("")
    fi
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
    else
        APP_RUNTIME_HOME="$APP_HOME/$instance_dir"
    fi

    # 设置实例相关变量
    PID_FILE="${APP_RUNTIME_HOME}/.app.pid"
    LOG_DIR="${APP_RUNTIME_HOME}/logs"
    LOG_FILE="${LOG_DIR}/${APP_NAME}.out"

    # 创建实例日志目录
    mkdir -p "$LOG_DIR"

    # 设置配置及JVM选项
    setup_config_opts
    setup_loader_opts
    setup_java_opts

    return 0
}

# 设置配置选项
setup_config_opts() {
    local runtime_config="${APP_RUNTIME_HOME}/appconfig/"
    local app_config="${APP_HOME}/appconfig/"
    
    # 设置活动配置文件
    ACTIVE_PROFILE="prod"
    CONFIG_OPTS="-Dspring.profiles.active=${ACTIVE_PROFILE}"
    
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
}

# 设置Loader选项
setup_loader_opts() {
    LOADER_OPTS="-Dloader.path=${PATCH_CLASSPATH},${APP_RUNTIME_HOME}/config/,${APP_HOME}/config/,${APP_HOME}/lib/"
}

# JVM 版本检测（设置 JAVA_MAJOR_VERSION）
detect_java_major_version() {
    local java_bin
    if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        java_bin="$JAVA_HOME/bin/java"
    else
        java_bin="java"
    fi
    local ver_str
    ver_str=$("$java_bin" -version 2>&1 | awk -F '"' '/version/ {print $2}')
    if [[ "$ver_str" =~ ^1\.([0-9]+)\. ]]; then
        JAVA_MAJOR_VERSION="${BASH_REMATCH[1]}"
    else
        JAVA_MAJOR_VERSION="${ver_str%%.*}"
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

    # 外置配置位置：与 startup.sh 位于相同目录
    local start_cfg="${APP_HOME}/start/jvm-env.sh"
    if [ -f "$start_cfg" ]; then
        # shellcheck disable=SC1090
        . "$start_cfg"
    fi
}

# 构建不同 JDK 版本的推荐 JVM 参数
build_java_opts_for_version() {
    detect_java_major_version
    load_jvm_tunables

    # 各版本按需构建参数
    case "$JAVA_MAJOR_VERSION" in
        8)
            # JDK 8: 使用 PermGen + 旧式 GC 日志
            local JDK8_OPTS=""
            JDK8_OPTS="$JDK8_OPTS -server"
            JDK8_OPTS="$JDK8_OPTS -Xms${JVM_XMS} -Xmx${JVM_XMX}"
            JDK8_OPTS="$JDK8_OPTS -XX:PermSize=${JVM_PERM_SIZE} -XX:MaxPermSize=${JVM_MAX_PERM_SIZE}"
            JDK8_OPTS="$JDK8_OPTS -XX:+UseG1GC -XX:MaxGCPauseMillis=${JVM_MAX_GC_PAUSE_MS} -XX:InitiatingHeapOccupancyPercent=${JVM_IHOP}"
            JDK8_OPTS="$JDK8_OPTS -XX:+ParallelRefProcEnabled -XX:+UseStringDeduplication"
            JDK8_OPTS="$JDK8_OPTS -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JVM_HEAP_DUMP_PATH} -XX:ErrorFile=${JVM_ERROR_FILE}"
            if [ -n "$JVM_THREAD_STACK_SIZE" ]; then
                JDK8_OPTS="$JDK8_OPTS -Xss${JVM_THREAD_STACK_SIZE}"
            fi
            # JDK 8 GC 日志（旧式）
            JDK8_OPTS="$JDK8_OPTS -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:${LOG_DIR}/gc.log"
            JDK8_OPTS="$JDK8_OPTS -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=${JVM_GC_LOG_FILECOUNT} -XX:GCLogFileSize=${JVM_GC_LOG_FILESIZE}"
            JAVA_VERSION_OPTS="$JDK8_OPTS"
            ;;
        11|17|21|25)
            # JDK 11/17/21/25: 使用 Metaspace + 新式 -Xlog GC 日志
            local MODERN_OPTS=""
            MODERN_OPTS="$MODERN_OPTS -server"
            MODERN_OPTS="$MODERN_OPTS -Xms${JVM_XMS} -Xmx${JVM_XMX}"
            MODERN_OPTS="$MODERN_OPTS -XX:MetaspaceSize=${JVM_METASPACE_SIZE} -XX:MaxMetaspaceSize=${JVM_MAX_METASPACE_SIZE}"
            MODERN_OPTS="$MODERN_OPTS -XX:+UseG1GC -XX:MaxGCPauseMillis=${JVM_MAX_GC_PAUSE_MS} -XX:InitiatingHeapOccupancyPercent=${JVM_IHOP}"
            MODERN_OPTS="$MODERN_OPTS -XX:+ParallelRefProcEnabled -XX:+UseStringDeduplication"
            MODERN_OPTS="$MODERN_OPTS -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JVM_HEAP_DUMP_PATH} -XX:ErrorFile=${JVM_ERROR_FILE}"
            if [ -n "$JVM_THREAD_STACK_SIZE" ]; then
                MODERN_OPTS="$MODERN_OPTS -Xss${JVM_THREAD_STACK_SIZE}"
            fi
            # JDK 11+ GC 日志（新式 -Xlog）
            MODERN_OPTS="$MODERN_OPTS -Xlog:gc*,safepoint:file=${LOG_DIR}/gc.log:time,level,tags:filecount=${JVM_GC_LOG_FILECOUNT},filesize=${JVM_GC_LOG_FILESIZE}"
            JAVA_VERSION_OPTS="$MODERN_OPTS"
            ;;
        *)
            # 兜底：JDK 9/10 或未识别版本，使用现代参数集
            local FALLBACK_OPTS=""
            FALLBACK_OPTS="$FALLBACK_OPTS -server"
            FALLBACK_OPTS="$FALLBACK_OPTS -Xms${JVM_XMS} -Xmx${JVM_XMX}"
            FALLBACK_OPTS="$FALLBACK_OPTS -XX:MetaspaceSize=${JVM_METASPACE_SIZE} -XX:MaxMetaspaceSize=${JVM_MAX_METASPACE_SIZE}"
            FALLBACK_OPTS="$FALLBACK_OPTS -XX:+UseG1GC -XX:MaxGCPauseMillis=${JVM_MAX_GC_PAUSE_MS} -XX:InitiatingHeapOccupancyPercent=${JVM_IHOP}"
            FALLBACK_OPTS="$FALLBACK_OPTS -XX:+ParallelRefProcEnabled -XX:+UseStringDeduplication"
            FALLBACK_OPTS="$FALLBACK_OPTS -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JVM_HEAP_DUMP_PATH} -XX:ErrorFile=${JVM_ERROR_FILE}"
            if [ -n "$JVM_THREAD_STACK_SIZE" ]; then
                FALLBACK_OPTS="$FALLBACK_OPTS -Xss${JVM_THREAD_STACK_SIZE}"
            fi
            FALLBACK_OPTS="$FALLBACK_OPTS -Xlog:gc*,safepoint:file=${LOG_DIR}/gc.log:time,level,tags:filecount=${JVM_GC_LOG_FILECOUNT},filesize=${JVM_GC_LOG_FILESIZE}"
            JAVA_VERSION_OPTS="$FALLBACK_OPTS"
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
    build_java_opts_for_version
}

# 检查应用是否运行
check_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
            echo $pid
            return 0
        fi
    fi
    echo ""
    return 1
}

# 检查Spring Boot应用启动状态
check_spring_boot_startup() {
    local instance_name="$1"
    local java_pid="$2"
    local max_wait_time=60  # 最大等待时间60秒
    local check_interval=2  # 每2秒检查一次
    local waited_time=0
    
    echo "=> 等待Spring Boot应用启动完成..."
    
    while [ $waited_time -lt $max_wait_time ]; do
        # 首先检查进程是否还存在
        if ! kill -0 $java_pid 2>/dev/null; then
            echo "=> 警告: 进程 $java_pid 已停止"
            rm -f "$PID_FILE"
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
                rm -f "$PID_FILE"
                return 1
            fi
            
            # 检查是否有严重错误
            if grep -qE "(Exception|Error.*startup|Failed to start|Unable to start|startup failed)" "$LOG_FILE" 2>/dev/null; then
                echo "=> 警告: 检测到启动错误"
                rm -f "$PID_FILE"
                return 1
            fi
        fi
        
        sleep $check_interval
        waited_time=$((waited_time + check_interval))
        echo "=> 等待中... (${waited_time}/${max_wait_time}秒)"
    done
    
    # 超时检查
    echo "=> 超时: 等待${max_wait_time}秒后仍未检测到启动完成标识"
    echo "=> 进程状态检查..."
    
    if kill -0 $java_pid 2>/dev/null; then
        echo "=> 警告: 进程仍在运行但未检测到启动完成，可能启动异常"
        echo "=> 建议检查日志: $LOG_FILE 和 $LOG_DIR"
        return 1
    else
        echo "=> 进程已停止，启动失败"
        rm -f "$PID_FILE"
        return 1
    fi
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
    
    # 使用 nohup 启动并将日志追加到日志文件，同时在后台运行
    nohup java $JAVA_OPTS $CONFIG_OPTS $LOADER_OPTS -jar $APP_JAR >> "$LOG_FILE" 2>&1 &
    local java_pid=$!
    echo $java_pid > "$PID_FILE"
    
    # 基础进程检查
    sleep 2
    if ! kill -0 $java_pid 2>/dev/null; then
        echo "=> $APP_NAME 实例 '$instance_name' 进程启动失败"
        rm -f "$PID_FILE"
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

# 停止单个应用实例
stop() {
    local instance_name="$1"
    
    if ! get_instance_config "$instance_name"; then
        echo "=> 错误: 实例 '$instance_name' 不存在"
        return 1
    fi
    
    pid=$(check_pid)
    if [ -z "$pid" ]; then
        echo "=> $APP_NAME 实例 '$instance_name' 未运行"
        return 0
    fi
    
    echo "=> 正在停止 $APP_NAME 实例 '$instance_name' (pid: $pid)..."
    kill $pid
    
    # 等待进程终止
    for ((i=1; i<=30; i++)); do
        if ! kill -0 $pid 2>/dev/null; then
            rm -f "$PID_FILE"
            echo "=> $APP_NAME 实例 '$instance_name' 已停止"
            return 0
        fi
        sleep 1
    done
    
    # 如果进程仍然存在，使用强制终止
    echo "=> $APP_NAME 实例 '$instance_name' 未能正常停止，正在强制终止..."
    kill -9 $pid
    rm -f "$PID_FILE"
    echo "=> $APP_NAME 实例 '$instance_name' 已被强制停止"
    return 0
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