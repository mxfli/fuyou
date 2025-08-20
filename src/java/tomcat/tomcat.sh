#!/bin/bash
#
# Tomcat 多实例管理脚本
# 版本要求: Tomcat 8.5+
# 使用方法: ./tomcat.sh [start|stop|restart|status] [实例名|all]
#

# 脚本所在目录
SCRIPT_HOME=$(cd "$(dirname "$0")" && pwd)
SERVERS_CONFIG="${SCRIPT_HOME}/servers.properties"

# 全局变量，由 get_instance_config 设置
TOMCAT_HOME=""
CATALINA_PID=""

# 加载并返回所有 tomcat 实例的 key
load_server_keys() {
    local keys=()
    if [ ! -f "$SERVERS_CONFIG" ]; then
        echo "错误: 配置文件不存在: $SERVERS_CONFIG" >&2
        return 1
    fi
    
    while IFS='=' read -r key value; do
        # 跳过空行和注释行, 并且只读取 tomcat 前缀的 key
        if [[ -n "$key" && ! "$key" =~ ^[[:space:]]*# && "$key" == tomcat* ]]; then
            keys+=("$(echo "$key" | xargs)")
        fi
    done < "$SERVERS_CONFIG"

    if [ ${#keys[@]} -eq 0 ]; then
        echo "错误: 在 $SERVERS_CONFIG 中没有找到 'tomcat' 前缀的配置." >&2
        return 1
    fi
    
    echo "${keys[@]}"
}

# 获取实例配置
# $1: instance_name
# 设置全局变量: TOMCAT_HOME, CATALINA_PID
get_instance_config() {
    local instance_name="$1"
    
    if [ ! -f "$SERVERS_CONFIG" ]; then
        echo "=> 错误: 配置文件不存在: $SERVERS_CONFIG"
        return 1
    fi

    local instance_path=$(grep "^${instance_name}=" "$SERVERS_CONFIG" | cut -d'=' -f2- | xargs)

    if [ -z "$instance_path" ]; then
        echo "=> 错误: 实例 '$instance_name' 在 $SERVERS_CONFIG 中未找到或路径为空."
        return 1
    fi

    # TOMCAT_HOME 是实例目录，路径相对于脚本位置
    TOMCAT_HOME_ABSOLUTE=$(cd "${SCRIPT_HOME}/${instance_path}" && pwd)

    if [ ! -d "$TOMCAT_HOME_ABSOLUTE" ]; then
        echo "=> 错误: Tomcat 实例目录不存在: $TOMCAT_HOME_ABSOLUTE"
        return 1
    fi
    
    if [ ! -f "${TOMCAT_HOME_ABSOLUTE}/bin/catalina.sh" ]; then
        echo "=> 错误: 在 ${TOMCAT_HOME_ABSOLUTE}/bin/ 中未找到 catalina.sh, 请确认是有效的 Tomcat 目录."
        return 1
    fi

    # 设置全局变量
    TOMCAT_HOME="$TOMCAT_HOME_ABSOLUTE"
    CATALINA_PID="${TOMCAT_HOME}/catalina.pid"
    return 0
}

# 检查Tomcat实例是否运行
check_pid() {
    if [ -f "$CATALINA_PID" ]; then
        local pid=$(cat "$CATALINA_PID")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0 # 正在运行
        fi
    fi
    echo ""
    return 1 # 未运行
}

# 启动单个Tomcat实例
start() {
    local instance_name="$1"
    
    if ! get_instance_config "$instance_name"; then
        return 1
    fi
    
    local pid=$(check_pid)
    if [ -n "$pid" ]; then
        echo "=> Tomcat 实例 '$instance_name' 已在运行中! (pid: $pid)"
        return 0
    fi

    echo "=> 正在启动 Tomcat 实例 '$instance_name'..."
    echo "=> Tomcat 目录: $TOMCAT_HOME"
    
    # 设置 CATALINA_PID 环境变量，以便 Tomcat 脚本创建 PID 文件
    export CATALINA_PID
    "${TOMCAT_HOME}/bin/startup.sh"
    
    echo "=> 等待 Tomcat 启动..."
    sleep 5
    pid=$(check_pid)
    if [ -n "$pid" ]; then
        echo "=> Tomcat 实例 '$instance_name' 启动成功! (pid: $pid)"
        echo "=> 日志文件位于: ${TOMCAT_HOME}/logs/catalina.out"
        return 0
    else
        echo "=> Tomcat 实例 '$instance_name' 启动失败，请检查日志: ${TOMCAT_HOME}/logs/catalina.out"
        return 1
    fi
}

# 停止单个Tomcat实例
stop() {
    local instance_name="$1"
    
    if ! get_instance_config "$instance_name"; then
        return 1
    fi
    
    local pid=$(check_pid)
    if [ -z "$pid" ]; then
        echo "=> Tomcat 实例 '$instance_name' 未运行."
        return 0
    fi
    
    echo "=> 正在停止 Tomcat 实例 '$instance_name' (pid: $pid)..."
    export CATALINA_PID # 确保 shutdown.sh 能找到 PID 文件
    "${TOMCAT_HOME}/bin/shutdown.sh"
    
    # 等待进程终止, 检查3次，每次间隔5秒
    for i in {1..3}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "=> Tomcat 实例 '$instance_name' 已成功停止."
            rm -f "$CATALINA_PID"
            return 0
        fi
        echo "=> 等待 Tomcat 停止... (检查 $i/3)"
        sleep 5
    done
    
    # 如果进程仍然存在，使用强制终止
    if kill -0 "$pid" 2>/dev/null; then
        echo "=> Tomcat 实例 '$instance_name' 未能正常停止，正在强制终止 (pid: $pid)..."
        kill -9 "$pid"
        sleep 1
        rm -f "$CATALINA_PID"
        echo "=> Tomcat 实例 '$instance_name' 已被强制停止."
    else
        echo "=> Tomcat 实例 '$instance_name' 已成功停止."
        rm -f "$CATALINA_PID"
    fi
    
    return 0
}

# 重启单个Tomcat实例
restart() {
    local instance_name="$1"
    echo "=> 正在重启 Tomcat 实例 '$instance_name'..."
    stop "$instance_name"
    if [ $? -ne 0 ]; then
        echo "=> 停止实例 '$instance_name' 失败, 中止重启."
        return 1
    fi
    sleep 2
    start "$instance_name"
}

# 滚动重启所有实例
restart_all() {
    local server_keys_str=$(load_server_keys)
    if [ $? -ne 0 ]; then
        echo "$server_keys_str" # 输出错误信息
        return 1
    fi
    read -r -a server_keys <<< "$server_keys_str"

    local total_count=${#server_keys[@]}
    local current_count=0
    
    echo "=> 开始滚动重启所有 Tomcat 实例 (共 $total_count 个)..."
    echo "=> 策略：逐个重启，如有失败则停止后续重启"
    echo ""
    
    for instance_name in "${server_keys[@]}"; do
        current_count=$((current_count + 1))
        echo "[$current_count/$total_count] 滚动重启实例: $instance_name"
        
        restart "$instance_name"
        
        if [ $? -ne 0 ]; then
            echo "✗ 实例 '$instance_name' 滚动重启失败."
            echo ""
            echo "=> 检测到重启失败，为保障业务连续性，停止后续实例的重启操作."
            return 1
        fi

        echo "✓ 实例 '$instance_name' 滚动重启成功."
        
        if [ $current_count -lt $total_count ]; then
            echo "=> 等待 10 秒确保服务稳定，然后重启下一个实例..."
            echo ""
            sleep 10
        fi
    done
    
    echo ""
    echo "=> 所有 Tomcat 实例滚动重启成功!"
    return 0
}

# 检查Tomcat实例状态
status() {
    local instance_name="$1"
    
    if ! get_instance_config "$instance_name"; then
        return 1
    fi
    
    local pid=$(check_pid)
    if [ -n "$pid" ]; then
        echo "=> Tomcat 实例 '$instance_name' 正在运行 (pid: $pid)"
        echo "=> Tomcat 目录: $TOMCAT_HOME"
        echo "=> 进程信息:"
        ps -f -p "$pid"
    else
        echo "=> Tomcat 实例 '$instance_name' 未运行."
    fi
}

# 主逻辑
main() {
    if [ $# -lt 2 ]; then
        echo "用法: $0 {start|stop|restart|status} {实例名|all}"
        exit 1
    fi

    local command="$1"
    local instance="$2"

    # 验证命令
    case "$command" in
        start|stop|restart|status)
            ;;
        *)
            echo "错误: 无效的命令 '$command'"
            echo "用法: $0 {start|stop|restart|status} {实例名|all}"
            exit 1
            ;;
    esac

    # 执行命令
    if [ "$instance" = "all" ]; then
        case "$command" in
            restart)
                restart_all
                ;;
            *)
                echo "错误: 目前仅支持 'restart all' 操作。"
                echo "如需启动、停止或检查所有实例，请逐个操作。"
                exit 1
                ;;
        esac
    else
        case "$command" in
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

# 运行主函数
main "$@"
exit 0