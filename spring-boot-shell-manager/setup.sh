#!/bin/bash
#
# Spring Boot 应用部署配置脚本
# 简化版：使用方法: ./setup.sh
#

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_HOME=$(cd "$SCRIPT_DIR/.." && pwd)

# 配置文件路径
SET_ENV_FILE="$SCRIPT_DIR/set-env.sh"
SERVERS_CONFIG="$APP_HOME/servers.properties"
JVM_ENV_FILE="$SCRIPT_DIR/jvm-env.sh"
SHUTDOWN_ENV_FILE="$SCRIPT_DIR/shutdown-env.sh"

# 检测 JAR 文件
detect_jar_files() {
    local jar_files=()
    echo "=> 正在检测 JAR 文件..."

    while IFS= read -r jar_file; do
        if [ -n "$jar_file" ]; then
            jar_files+=("$jar_file")
        fi
    done < <(find "$APP_HOME" -maxdepth 1 -mindepth 1 -name "*.jar" -type f -print0 2>/dev/null | xargs -0 ls -1t 2>/dev/null)

    if [ ${#jar_files[@]} -eq 0 ]; then
        echo "=> 没有找到 JAR 文件"
        return 1
    fi

    echo "=> 找到 ${#jar_files[@]} 个 JAR 文件"
    for i in "${!jar_files[@]}"; do
        echo "  $((i+1)): $(basename "${jar_files[$i]}")"
    done
    echo ""

    return 0
}

# 选择并解析 JAR 文件
select_and_parse_jar() {
    detect_jar_files

    if [ $? -ne 0 ]; then
        echo "=> 错误: 请确保 JAR 文件位于应用目录"
        return 1
    fi

    local jar_files=()
    while IFS= read -r jar_file; do
        if [ -n "$jar_file" ]; then
            jar_files+=("$jar_file")
        fi
    done < <(find "$APP_HOME" -maxdepth 1 -mindepth 1 -name "*.jar" -type f -print0 2>/dev/null | xargs -0 ls -1t 2>/dev/null)

    if [ ${#jar_files[@]} -eq 1 ]; then
        echo "=> 自动选择唯一 JAR: $(basename "${jar_files[0]}")"
        local selected_jar="${jar_files[0]}"
    else
        while true; do
            read -p "请选择 JAR 编号 (1-${#jar_files[@]}): " choice
            if [ -z "$choice" ]; then
                echo "=> 请输入数字"
                continue
            fi
            if [ "$choice" =~ ^[0-9]+$ ] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#jar_files[@]} ]; then
                local selected_jar="${jar_files[$((choice-1))]}"
                break
            else
                echo "=> 请输入有效数字"
            fi
        done
    fi

    local jar_name=$(basename "$selected_jar" .jar)

    # 从 JAR 文件名解析
    if [[ "$jar_name" =~ ^(.+)-([0-9]+\.[0-9]+.*-SNAPSHOT)$ ]]; then
        APP_NAME="${BASH_REMATCH[1]}"
        APP_VERSION="${BASH_REMATCH[2]}"
    elif [[ "$jar_name" =~ ^(.+)-([0-9]+\.[0-9]+.*)$ ]]; then
        APP_NAME="${BASH_REMATCH[1]}"
        APP_VERSION="${BASH_REMATCH[2]}"
    elif [[ "$jar_name" =~ ^(.+)-(SNAPSHOT|RELEASE)$ ]]; then
        APP_NAME="${BASH_REMATCH[1]}"
        APP_VERSION="${BASH_REMATCH[2]}"
    else
        APP_NAME="$jar_name"
        APP_VERSION=""
    fi

    return 0
}

# 配置应用信息
configure_app_info() {
    select_and_parse_jar

    if ! unzip -p "$APP_HOME/${APP_NAME}.jar" META-INF/MANIFEST.MF 2>/dev/null | grep -qi "^Main-Class:"; then
        MAIN_CLASS=""
        echo "=> Thin JAR 模式，无需配置主类"
    else
        MAIN_CLASS=$(unzip -p "$APP_HOME/${APP_NAME}.jar" META-INF/MANIFEST.MF 2>/dev/null | \
            grep "^Main-Class:" | \
            sed 's/^Main-Class:[[:space:]]*//' | \
            grep -v '^$')

        if [ -n "$MAIN_CLASS" ]; then
            read -p "使用检测到的主类 $MAIN_CLASS? [y/N]: " use_main
            if [[ ! "$use_main" =~ ^[Yy]$ ]]; then
                MAIN_CLASS=""
            fi
        fi

        if [ -z "$MAIN_CLASS" ]; then
            read -p "输入主类（如 com.example.App）[可选]: " main_class_input
            MAIN_CLASS="$main_class_input"
        fi
    fi

    return 0
}

# 配置多实例
configure_multi_instances() {
    echo "=> 配置多实例模式"
    read -p "实例数量 [默认: 1]: " instance_count
    instance_count=${instance_count:-1}

    if [[ "$instance_count" =~ ^[0-9]+$ ]] && [ "$instance_count" -ge 1 ] && [ "$instance_count" -le 3 ]; then
        INSTANCE_COUNT=$instance_count
    else
        echo "=> 默认使用 1 个实例"
        INSTANCE_COUNT=1
    fi

    if [ $instance_count -eq 1 ]; then
        echo "=> 单实例模式"
        return 0
    fi

    if [ -f "$SERVERS_CONFIG" ]; then
        echo "=> 配置文件已存在，将创建备份"
        mkdir -p "$APP_HOME/back"
        cp "$SERVERS_CONFIG" "$APP_HOME/back/servers.properties"
    fi

    read -p "基础端口 [默认: 8080]: " base_port
    base_port=${base_port:-8080}

    {
        echo "# 多实例配置"
        echo "格式：实例名=实例目录"
        echo "生成于 $(date)"
        echo ""
    } > "$SERVERS_CONFIG"

    for i in $(seq 1 "$instance_count"); do
        local port=$((base_port + i - 1))
        local instance_name="instance$i"
        local instance_dir="instance-$port"

        echo "$instance_name=$instance_dir" >> "$SERVERS_CONFIG"
        mkdir -p "$APP_HOME/$instance_dir/logs"
        mkdir -p "$APP_HOME/$instance_dir/appconfig"
    done

    echo "=> 已创建 $instance_count 个实例"
}

# 配置 Spring Profile
configure_spring_profiles() {
    read -p "Spring Profile [默认: default]: " profile_input
    SPRING_PROFILES_ACTIVE=${profile_input:-default}
}

# 配置 JVM 参数
configure_jvm_memory() {
    echo "=> 配置 JVM 参数"
    read -p "初始堆内存 [默认: 2g]: " xms
    xms=${xms:-2g}
    read -p "最大堆内存 [默认: 4g]: " xmx
    xmx=${xmx:-4g}

    JVM_XMS="$xms"
    JVM_XMX="$xmx"
}

# 生成配置文件
generate_configs() {
    # set-env.sh
    {
        echo "# Spring Boot 环境配置"
        echo "APP_NAME=\"$APP_NAME\""
        echo "APP_VERSION=\"${APP_VERSION:-}\""
        [ -n "$MAIN_CLASS" ] && echo "MAIN_CLASS=\"$MAIN_CLASS\"" || echo "# MAIN_CLASS 未设置"
        echo "SPRING_PROFILES_ACTIVE=\"$SPRING_PROFILES_ACTIVE\""
    } > "$SET_ENV_FILE"

    # jvm-env.sh
    {
        echo "# JVM 参数配置"
        echo "JVM_XMS=\"$JVM_XMS\""
        echo "JVM_XMX=\"$JVM_XMX\""
    } > "$JVM_ENV_FILE"

    # shutdown-env.sh
    {
        echo "# 优雅停止配置"
        echo "GRACEFUL_SHUTDOWN_TIMEOUT=30"
        echo "FORCE_KILL_TIMEOUT=10"
    } > "$SHUTDOWN_ENV_FILE"

    chmod +x "$SET_ENV_FILE" "$JVM_ENV_FILE" "$SHUTDOWN_ENV_FILE"
}

# 显示摘要
show_summary() {
    echo ""
    echo "=== 配置完成 ==="
    echo ""
    echo "应用名称: $APP_NAME"
    echo "应用版本: ${APP_VERSION:-未设置}"
    echo "Spring Profile: $SPRING_PROFILES_ACTIVE"
    echo "实例数量: ${INSTANCE_COUNT:-1}"
    if [ -n "${JVM_XMS:-}" ]; then
        echo "JVM 内存: $JVM_XMS / $JVM_XMX"
    fi
    if [ -n "$MAIN_CLASS" ]; then
        echo "主类: $MAIN_CLASS"
    fi
    echo ""
    echo "配置文件已生成："
    echo "  - $SET_ENV_FILE"
    echo "  - $JVM_ENV_FILE"
    echo "  - $SHUTDOWN_ENV_FILE"
    if [ "${INSTANCE_COUNT:-1}" -gt 1 ]; then
        echo "  - $SERVERS_CONFIG"
    fi
}

# 主函数
main() {
    configure_app_info
    configure_multi_instances
    configure_spring_profiles
    configure_jvm_memory
    generate_configs
    show_summary
    echo "=> 配置完成！"
}

main "$@"