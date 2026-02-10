#!/bin/bash
#
# Spring Boot 应用启动管理脚本 (fuyou 极简版)
#

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_HOME=$(cd "$SCRIPT_DIR/.." && pwd)

# 基础函数
log_info() { echo "=> $*"; }
log_error() { echo "=> 错误: $*"; }

# 加载配置
[ -f "$SCRIPT_DIR/set-env.sh" ] && . "$SCRIPT_DIR/set-env.sh"
[ -f "$SCRIPT_DIR/jvm-env.sh" ] && . "$SCRIPT_DIR/jvm-env.sh"
[ -f "$SCRIPT_DIR/shutdown-env.sh" ] && . "$SCRIPT_DIR/shutdown-env.sh"

SERVERS_CONFIG="$APP_HOME/servers.properties"
# 确定当前要启动的 JAR 文件
if [ -n "$APP_VERSION" ]; then
    APP_JAR="${APP_HOME}/${APP_NAME}-${APP_VERSION}.jar"
else
    APP_JAR="${APP_HOME}/${APP_NAME}.jar"
fi

# 获取文件修改时间 (macOS/Linux 兼容)
get_mtime() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# 检测 Java 版本并构建参数
build_java_cmd() {
    local java_bin="java"
    [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ] && java_bin="$JAVA_HOME/bin/java"
    
    if ! command -v "$java_bin" >/dev/null 2>&1; then
        log_error "找不到 Java 可执行文件"
        return 1
    fi

    # 获取主版本号 (兼容 1.8.x -> 8, 17.x -> 17)
    local v_str=$("$java_bin" -version 2>&1 | head -1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)
    local v_major=${v_str%%.*}
    [ "$v_major" = "1" ] && v_major=$(echo "$v_str" | cut -d'.' -f2)
    v_major=${v_major:-8}  # 默认假设 JDK 8

    # 构建 JVM 参数数组
    JAVA_CMD=("$java_bin")
    JAVA_CMD+=("-server" "-Xms${JVM_XMS:-2g}" "-Xmx${JVM_XMX:-4g}")
    JAVA_CMD+=("-XX:MetaspaceSize=128m" "-XX:MaxMetaspaceSize=512m" "-XX:+UseG1GC")
    JAVA_CMD+=("-Dlogging.file.path=${LOG_DIR}" "-Duser.dir=${APP_HOME}" "-Dspring.profiles.active=${SPRING_PROFILES_ACTIVE:-default}")
    
    # 自动设置端口 (如果实例目录包含端口号)
    [[ "$APP_RUNTIME_HOME" =~ -([0-9]+)$ ]] && JAVA_CMD+=("-Dserver.port=${BASH_REMATCH[1]}")

    # GC 日志 (8使用旧参数，9+使用新参数)
    if [ "$v_major" -le 8 ]; then
        JAVA_CMD+=("-Xloggc:${LOG_DIR}/gc.log" "-XX:+PrintGCDetails" "-XX:+PrintGCDateStamps")
    else
        JAVA_CMD+=("-Xlog:gc*:file=${LOG_DIR}/gc.log:time")
    fi

    # 外部依赖路径 (Fat JAR 模式)
    [ -d "$APP_HOME/config" ] && JAVA_CMD+=("-Dloader.path=${APP_HOME}/config")
}

# 检查进程是否属于本应用 (忽略版本号差异)
check_pid() {
    [ ! -f "$PID_FILE" ] && return 1
    local pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -z "$pid" ] || [[ ! "$pid" =~ ^[0-9]+$ ]] && { rm -f "$PID_FILE"; return 1; }

    if kill -0 "$pid" 2>/dev/null; then
        local cmdline=$(ps -p "$pid" -o command= 2>/dev/null)
        # 核心判定：必须包含 java 且 jar 文件名匹配前缀
        if echo "$cmdline" | grep -q "java" && [[ "$cmdline" =~ ${APP_NAME}(-[0-9]+\.[0-9]+.*)?\.jar ]]; then
            echo "$pid"
            return 0
        fi
    fi
    return 1
}

# 设置实例运行环境
setup_instance_env() {
    local name="$1"
    APP_RUNTIME_HOME="$APP_HOME"
    
    if [ -f "$SERVERS_CONFIG" ] && [ "$name" != "all" ]; then
        local dir=$(grep "^${name}=" "$SERVERS_CONFIG" | head -1 | cut -d'=' -f2)
        [ -n "$dir" ] && APP_RUNTIME_HOME="$APP_HOME/$dir"
    fi

    PID_FILE="$APP_RUNTIME_HOME/.app.pid"
    LOG_DIR="$APP_RUNTIME_HOME/logs"
    LOG_FILE="$LOG_DIR/${APP_NAME}.out"
    
    if ! mkdir -p "$LOG_DIR"; then
        log_error "无法创建日志目录: $LOG_DIR"
        return 1
    fi
}

start_instance() {
    setup_instance_env "$1" || return 1
    local pid=$(check_pid)
    [ -n "$pid" ] && { log_info "应用已在运行 (pid: $pid)"; return 0; }

    build_java_cmd || return 1
    
    log_info "正在启动 $APP_NAME ($1)..."
    [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "${LOG_FILE}.bak"
    
    # 使用数组安全执行启动命令
    nohup "${JAVA_CMD[@]}" -jar "$APP_JAR" > "$LOG_FILE" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"
    
    # 初步检查
    sleep 2
    if kill -0 "$new_pid" 2>/dev/null; then
        log_info "启动成功 (pid: $new_pid)，日志: $LOG_FILE"
    else
        log_error "进程启动后立即退出，请检查日志: $LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi
}

stop_instance() {
    setup_instance_env "$1"
    local pid=$(check_pid)
    if [ -z "$pid" ]; then
        log_info "应用未运行 ($1)"
        return 0
    fi

    log_info "正在停止进程 $pid..."
    kill -TERM "$pid" 2>/dev/null
    
    local timeout=${GRACEFUL_SHUTDOWN_TIMEOUT:-30}
    while [ $timeout -gt 0 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        ((timeout--))
    done

    if kill -0 "$pid" 2>/dev/null; then
        log_info "强制杀掉进程..."
        kill -KILL "$pid" 2>/dev/null
    fi
    rm -f "$PID_FILE"
    log_info "已停止"
}

status_instance() {
    setup_instance_env "$1"
    local pid=$(check_pid)
    if [ -n "$pid" ]; then
        echo "=> $1: 运行中 (pid: $pid)"
        ps -p "$pid" -o pid,comm,etime=
    else
        echo "=> $1: 未运行"
    fi
}

# 处理全量或单实例命令
handle_cmd() {
    local cmd="$1"
    local target="$2"

    if [ "$target" = "all" ] && [ -f "$SERVERS_CONFIG" ]; then
        local instances=$(grep -v "^#" "$SERVERS_CONFIG" | cut -d'=' -f1)
        while IFS= read -r ins; do
            [ -n "$ins" ] && ${cmd}_instance "$ins"
        done <<< "$instances"
    else
        # 如果未指定 target 且存在多实例，提示选择
        if [ -z "$target" ] && [ -f "$SERVERS_CONFIG" ]; then
            echo "当前配置了多实例，请指定实例名或 'all'："
            grep -v "^#" "$SERVERS_CONFIG" | cut -d'=' -f1 | sed 's/^/ - /'
            return 1
        fi
        ${cmd}_instance "${target:-server}"
    fi
}

main() {
    case "$1" in
        start|stop|status) handle_cmd "$1" "$2" ;;
        restart) handle_cmd "stop" "$2"; sleep 2; handle_cmd "start" "$2" ;;
        *) echo "用法: $0 {start|stop|restart|status} [实例名|all]" ;;
    esac
}

main "$@"
