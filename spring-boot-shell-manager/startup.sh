#!/bin/bash
#
# Spring Boot 应用启动管理脚本
# 使用方法: ./startup.sh [start|stop|restart|status] [实例名|all]
#

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_HOME=$(cd "$SCRIPT_DIR/.." && pwd)

# 加载环境配置
[ -f "$SCRIPT_DIR/set-env.sh" ] && . "$SCRIPT_DIR/set-env.sh"

APP_JAR="${APP_HOME}/${APP_NAME}.jar"
SERVERS_CONFIG="$APP_HOME/servers.properties"
PATCH_CLASSPATH="$APP_HOME/patch_classpath"
MAX_WAIT_TIME=60
CHECK_INTERVAL=2

# 加载 JVM 和优雅停止配置
[ -f "$SCRIPT_DIR/jvm-env.sh" ] && . "$SCRIPT_DIR/jvm-env.sh"
[ -f "$SCRIPT_DIR/shutdown-env.sh" ] && . "$SCRIPT_DIR/shutdown-env.sh"

# 日志函数
log_info() { echo "=> $*"; }
log_warn() { echo "=> 警告: $*"; }
log_error() { echo "=> 错误: $*"; }

# 获取文件修改时间
get_mtime() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# 检测 JAR 文件和类型
detect_jar() {
    local current_mtime
    current_mtime=$(get_mtime "$APP_JAR")
    JAR_TYPE=""
    MAIN_CLASS=""

    if [[ "$APP_VERSION" =~ -SNAPSHOT ]]; then
        JAR_TYPE="thin"
    elif jar tf "$APP_JAR" 2>/dev/null | grep -q "^BOOT-INF/"; then
        JAR_TYPE="fat"
        MAIN_CLASS="org.springframework.boot.loader.JarLauncher"
    fi

    return 0
}

# 设置配置选项
setup_config_opts() {
    ACTIVE_PROFILE="${SPRING_PROFILES_ACTIVE:-default}"
    CONFIG_OPTS="-Dspring.profiles.active=${ACTIVE_PROFILE}"

    # 端口检测
    INSTANCE_PORT=$(ls -d "$APP_HOME/instance-"*/ 2>/dev/null | grep -oE '[0-9]+$' | head -1)

    if [ -n "$INSTANCE_PORT" ]; then
        CONFIG_OPTS="$CONFIG_OPTS -Dserver.port=${INSTANCE_PORT}"
        log_info "自动端口: $INSTANCE_PORT"
    fi

    # 配置文件路径
    local runtime_config="$APP_HOME/runtime"
    local app_config="$APP_HOME/appconfig"

    [ -d "$runtime_config" ] && CONFIG_OPTS="$CONFIG_OPTS -Dspring.config.location=file:${runtime_config}"
    [ -d "$app_config" ] && CONFIG_OPTS="$CONFIG_OPTS -Dspring.config.location=file:${app_config}"

    return 0
}

# 设置 Loader 选项
setup_loader_opts() {
    if [ "$JAR_TYPE" = "fat" ]; then
        LOADER_OPTS="-Dloader.path=${PATCH_CLASSPATH},${APP_HOME}/config/"
    else
        LOADER_OPTS=""
    fi
}

# 检测 Java 版本
detect_java() {
    local java_bin="java"
    if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        java_bin="$JAVA_HOME/bin/java"
    fi

    if ! command -v "$java_bin" >/dev/null 2>&1; then
        log_error "无法找到 Java"
        return 1
    fi

    local version=$("$java_bin" -version 2>&1)
    if [[ "$version" =~ ^.*([0-9]+\.[0-9]+).* ]]; then
        JAVA_MAJOR_VERSION="${BASH_REMATCH[1]}"
    fi

    return 0
}

# 构建 JVM 选项
build_java_opts() {
    if ! detect_java; then
        return 1
    fi

    local common_opts="-server -Xms${JVM_XMS:-2g} -Xmx${JVM_XMX:-4g} -XX:MetaspaceSize=${JVM_METASPACE_SIZE:-128m} -XX:MaxMetaspaceSize=${JVM_MAX_METASPACE_SIZE:-512m}"

    case "$JAVA_MAJOR_VERSION" in
        8)
            common_opts="$common_opts -XX:+UseG1GC -XX:+PrintGCDetails"
            JAVA_OPTS="$common_opts -Xloggc:${LOG_DIR}/gc.log"
            ;;
        *)
            common_opts="$common_opts -XX:+UseG1GC -Xlog:gc*:file=${LOG_DIR}/gc.log:time"
            JAVA_OPTS="$common_opts"
            ;;
    esac

    JAVA_OPTS="$JAVA_OPTS -Dlogging.file.path=${LOG_DIR} -Duser.dir=${APP_HOME}"
    return 0
}

# 获取实例配置
get_instance_config() {
    local instance_name="$1"

    # 读取配置
    if [ -f "$SERVERS_CONFIG" ]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            key=${key#"${key%%[![:space:]]*}"} key=${key%"${key##*[![:space:]]}"}
            value=${value#"${value%%[![:space:]]*}"} value=${value%"${value##*[![:space:]]}"}

            if [ "$instance_name" = "$key" ]; then
                APP_RUNTIME_HOME="$APP_HOME/$value"
                echo "=> 实例: $key -> $value"
                return 0
            fi
        done < "$SERVERS_CONFIG"
    fi

    echo "=> 使用默认实例"
    APP_RUNTIME_HOME="$APP_HOME"
}

# 构建 Java 命令
build_cmd() {
    JAVA_CMD=("java")
    [ -n "$JAVA_OPTS" ] && read -ra opts <<< "$JAVA_OPTS" && JAVA_CMD+=("${opts[@]}")
    [ -n "$CONFIG_OPTS" ] && read -ra opts <<< "$CONFIG_OPTS" && JAVA_CMD+=("${opts[@]}")
    [ -n "$LOADER_OPTS" ] && read -ra opts <<< "$LOADER_OPTS" && JAVA_CMD+=("${opts[@]}")
    JAVA_CMD+=("-jar" "$APP_JAR")
}

# 检查进程
check_pid() {
    [ ! -f "$PID_FILE" ] && return 1

    local pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -z "$pid" ] && { rm -f "$PID_FILE"; return 1; }
    [[ ! "$pid" =~ ^[0-9]+$ ]] && { rm -f "$PID_FILE"; return 1; }

    if kill -0 "$pid" 2>/dev/null; then
        [ -n "$APP_JAR" ] && ps -p "$pid" -o command= 2>/dev/null | grep -q "java.*$APP_JAR" && echo "$pid"
    fi

    return 1
}

# 启动应用
start() {
    local instance_name="$1"

    if ! get_instance_config "$instance_name"; then
        log_error "实例不存在"
        return 1
    fi

    PID_FILE="$APP_RUNTIME_HOME/.app.pid"
    LOG_DIR="$APP_RUNTIME_HOME/logs"
    LOG_FILE="$LOG_DIR/${APP_NAME}.out"

    [ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR"
    [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$LOG_FILE.bak"

    detect_jar
    setup_config_opts
    setup_loader_opts

    if ! build_java_opts; then
        return 1
    fi

    build_cmd

    log_info "启动 $APP_NAME..."
    log_info "目录: $APP_RUNTIME_HOME"

    echo "${JAVA_CMD[@]}" > "$LOG_FILE" 2>&1 &
    local java_pid=$!
    echo "$java_pid" > "$PID_FILE"

    sleep 2
    [ ! -s "$PID_FILE" ] && { rm -f "$PID_FILE"; log_error "启动失败"; return 1; }

    sleep "$MAX_WAIT_TIME"

    if ! kill -0 "$java_pid" 2>/dev/null; then
        log_error "进程已停止"
        rm -f "$PID_FILE"
        return 1
    fi

    if grep -q "Started.*in.*seconds" "$LOG_FILE" 2>/dev/null; then
        log_info "启动成功 (pid: $java_pid)"
        return 0
    fi

    log_warn "未检测到启动完成"
    return 1
}

# 停止应用
stop() {
    local instance_name="$1"
    get_instance_config "$instance_name"

    PID_FILE="$APP_RUNTIME_HOME/.app.pid"
    LOG_DIR="$APP_RUNTIME_HOME/logs"
    LOG_FILE="$LOG_DIR/${APP_NAME}.out"

    local pid=$(check_pid)

    if [ -z "$pid" ]; then
        echo "=> 未运行"
        return 0
    fi

    log_info "停止进程 $pid..."

    # 优雅停止
    kill -TERM "$pid" 2>/dev/null
    local count=0
    while [ $count -lt "$GRACEFUL_SHUTDOWN_TIMEOUT" ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
    done

    # 强制停止
    if kill -0 "$pid" 2>/dev/null; then
        log_info "强制停止进程"
        kill -KILL "$pid" 2>/dev/null
    fi

    rm -f "$PID_FILE"
    log_info "已停止"
}

# 重启应用
restart() {
    local instance_name="$1"
    stop "$instance_name"
    sleep 2
    start "$instance_name"
}

# 查看状态
status() {
    local instance_name="$1"
    get_instance_config "$instance_name"

    PID_FILE="$APP_RUNTIME_HOME/.app.pid"
    LOG_DIR="$APP_RUNTIME_HOME/logs"
    LOG_FILE="$LOG_DIR/${APP_NAME}.out"

    local pid=$(check_pid)

    if [ -n "$pid" ]; then
        echo "=> 运行中 (pid: $pid)"
        ps -p "$pid" -o pid,comm,etime=
    else
        echo "=> 未运行"
    fi
}

# 显示可用实例
show_instances() {
    if [ -f "$SERVERS_CONFIG" ]; then
        local i=0
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            i=$((i + 1))
            echo "$i. $key -> $APP_HOME/$value"
        done < "$SERVERS_CONFIG"
    else
        echo "1. server -> $APP_HOME"
    fi
}

# 命令处理
main() {
    local command="$1"
    local instance="$2"

    case "$command" in
        start)
            [ -z "$instance" ] && instance="all"
            if [ "$instance" = "all" ]; then
                read_servers_sorted || instance="server"
            fi
            [ "$instance" = "all" ] && echo "=> 启动所有实例" || echo "=> 启动 $instance"
            start "$instance"
            ;;
        stop)
            [ -z "$instance" ] && instance="all"
            if [ "$instance" = "all" ]; then
                read_servers_sorted || instance="server"
            fi
            [ "$instance" = "all" ] && echo "=> 停止所有实例" || echo "=> 停止 $instance"
            stop "$instance"
            ;;
        restart)
            [ -z "$instance" ] && instance="all"
            if [ "$instance" = "all" ]; then
                read_servers_sorted || instance="server"
            fi
            [ "$instance" = "all" ] && echo "=> 重启所有实例" || echo "=> 重启 $instance"
            restart "$instance"
            ;;
        status)
            [ -z "$instance" ] && instance="all"
            if [ "$instance" = "all" ]; then
                read_servers_sorted || instance="server"
            fi
            [ "$instance" = "all" ] && echo "=> 检查所有实例" || echo "=> 检查 $instance"
            status "$instance"
            ;;
        *)
            echo "用法: $0 {start|stop|restart|status} [实例名|all]"
            [ $# -eq 0 ] && { show_instances; echo ""; echo "或直接运行菜单"; }
            ;;
    esac
}

read_servers_sorted() {
    if [ -f "$SERVERS_CONFIG" ]; then
        local list=()
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            list+=("$key")
        done < "$SERVERS_CONFIG"
        local choice
        read -p "选择实例 [${list[*]} - a (all)]: " choice
        instance=$choice
        [ "$choice" = "a" ] || [ "$choice" = "all" ] && instance="all"
    fi
}

main "$@"