#!/bin/bash
#
# Spring Boot 应用部署配置脚本 (fuyou 极简版)
#

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_HOME=$(cd "$SCRIPT_DIR/.." && pwd)

# 配置文件路径
SET_ENV_FILE="$SCRIPT_DIR/set-env.sh"
SERVERS_CONFIG="$APP_HOME/servers.properties"
JVM_ENV_FILE="$SCRIPT_DIR/jvm-env.sh"
SHUTDOWN_ENV_FILE="$SCRIPT_DIR/shutdown-env.sh"

# 工具检查
check_tools() {
    for tool in unzip java; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "=> 错误: 系统缺少命令 '$tool'，请先安装"
            exit 1
        fi
    done
}

# 选择 JAR 并解析信息
select_jar_and_parse() {
    echo "=> 正在检测 JAR 文件..."
    local jar_files
    # 使用简洁的查找和排序方式
    IFS=$'\n' jar_files=($(find "$APP_HOME" -maxdepth 1 -name "*.jar" -type f | xargs ls -1t 2>/dev/null))
    
    if [ ${#jar_files[@]} -eq 0 ]; then
        echo "=> 错误: 在 $APP_HOME 下未找到任何 .jar 文件"
        exit 1
    fi

    local selected_jar=""
    if [ ${#jar_files[@]} -eq 1 ]; then
        selected_jar="${jar_files[0]}"
        echo "=> 自动选择唯一 JAR: $(basename "$selected_jar")"
    else
        echo "=> 找到多个 JAR 文件："
        for i in "${!jar_files[@]}"; do
            echo "  $((i+1)): $(basename "${jar_files[$i]}")"
        done
        while true; do
            read -p "请选择 JAR 编号 (1-${#jar_files[@]}): " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#jar_files[@]} ]; then
                selected_jar="${jar_files[$((choice-1))]}"
                break
            fi
            echo "=> 输入无效，请输入有效编号"
        done
    fi

    FULL_JAR_PATH="$selected_jar"
    local jar_file_name=$(basename "$selected_jar" .jar)
    
    # 极简解析 APP_NAME 和 APP_VERSION (支持 name-1.0.0 或 name 格式)
    if [[ "$jar_file_name" =~ ^(.*)-([0-9]+\.[0-9]+.*)$ ]]; then
        APP_NAME="${BASH_REMATCH[1]}"
        APP_VERSION="${BASH_REMATCH[2]}"
    else
        APP_NAME="$jar_file_name"
        APP_VERSION=""
    fi
}

# 配置应用主类
configure_main_class() {
    local manifest_main=$(unzip -p "$FULL_JAR_PATH" META-INF/MANIFEST.MF 2>/dev/null | grep "^Main-Class:" | sed 's/^Main-Class:[[:space:]]*//' | tr -d '\r')
    
    if [ -n "$manifest_main" ]; then
        # 针对 Spring Boot Fat JAR 的常见 Launcher 进行友好提示
        if [[ "$manifest_main" == "org.springframework.boot.loader."* ]]; then
            echo "=> 检测到 Spring Boot Fat JAR，将使用内置 Launcher"
            MAIN_CLASS=""
        else
            read -p "检测到主类 $manifest_main，是否使用? [Y/n]: " confirm
            if [[ "${confirm:-y}" =~ ^[Yy]$ ]]; then
                MAIN_CLASS="$manifest_main"
            fi
        fi
    fi

    if [ -z "$MAIN_CLASS" ] && [ -z "$manifest_main" ]; then
        read -p "未检测到主类，是否手动输入? (直接回车跳过): " input_main
        MAIN_CLASS="$input_main"
    fi
}

# 配置多实例与端口
configure_instances() {
    read -p "实例数量 [默认: 1]: " count
    INSTANCE_COUNT=${count:-1}
    
    if [ "$INSTANCE_COUNT" -le 1 ]; then
        echo "=> 单实例模式"
        return
    fi

    [ -f "$SERVERS_CONFIG" ] && cp "$SERVERS_CONFIG" "${SERVERS_CONFIG}.bak" && echo "=> 已备份旧配置到 .bak"
    
    read -p "起始端口 [默认: 8080]: " port
    local base_port=${port:-8080}

    {
        echo "# 多实例配置 - 生成于 $(date)"
        for i in $(seq 1 "$INSTANCE_COUNT"); do
            local p=$((base_port + i - 1))
            local instance_dir="instance-$p"
            echo "instance$i=$instance_dir"
            mkdir -p "$APP_HOME/$instance_dir/logs" "$APP_HOME/$instance_dir/appconfig"
        done
    } > "$SERVERS_CONFIG"
    echo "=> 已创建 $INSTANCE_COUNT 个实例配置"
}

# 写入配置文件
write_configs() {
    # set-env.sh
    {
        echo "# 应用环境配置"
        echo "APP_NAME=\"$APP_NAME\""
        echo "APP_VERSION=\"$APP_VERSION\""
        [ -n "$MAIN_CLASS" ] && echo "MAIN_CLASS=\"$MAIN_CLASS\""
        read -p "Spring Profile [默认: default]: " profile
        echo "SPRING_PROFILES_ACTIVE=\"${profile:-default}\""
    } > "$SET_ENV_FILE"

    # jvm-env.sh
    echo "=> JVM 参数配置"
    read -p "初始堆内存 (Xms) [默认: 2g]: " xms
    read -p "最大堆内存 (Xmx) [默认: 4g]: " xmx
    {
        echo "# JVM 参数配置"
        echo "JVM_XMS=\"${xms:-2g}\""
        echo "JVM_XMX=\"${xmx:-4g}\""
    } > "$JVM_ENV_FILE"

    # shutdown-env.sh (极简默认值)
    [ ! -f "$SHUTDOWN_ENV_FILE" ] && echo -e "GRACEFUL_SHUTDOWN_TIMEOUT=30\nFORCE_KILL_TIMEOUT=10" > "$SHUTDOWN_ENV_FILE"

    chmod +x "$SET_ENV_FILE" "$JVM_ENV_FILE" "$SHUTDOWN_ENV_FILE"
}

main() {
    check_tools
    select_jar_and_parse
    configure_main_class
    configure_instances
    write_configs
    echo "=> 所有配置已生成完成！"
}

main "$@"
