#!/bin/bash
#
# Spring Boot 应用部署配置脚本
# 使用方法: ./setup.sh
# 功能: 交互式配置应用名称、版本、实例数量等参数
#

# 获取脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
APP_HOME=$(cd "$SCRIPT_DIR/.." && pwd)

# 配置文件路径
SET_ENV_FILE="$SCRIPT_DIR/set-env.sh"
SERVERS_CONFIG="$APP_HOME/servers.properties"
JVM_ENV_FILE="$SCRIPT_DIR/jvm-env.sh"
SHUTDOWN_ENV_FILE="$SCRIPT_DIR/shutdown-env.sh"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局数组存储检测到的JAR文件
DETECTED_JAR_FILES=()

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示欢迎信息
show_welcome() {
    echo "========================================"
    echo "  Spring Boot 应用部署配置向导"
    echo "========================================"
    echo ""
    print_info "此脚本将帮助您配置 Spring Boot 应用的部署环境"
    print_info "配置内容包括: 应用信息、实例配置、JVM参数等"
    echo ""
}

# 自动检测JAR文件
detect_jar_files() {
    local jar_files=()
    
    print_info "正在检测JAR文件..."
    print_info "搜索目录: $APP_HOME"
    
    # 在应用根目录查找JAR文件
    # 使用通配符在当前目录查找JAR文件，仅匹配一层
    while IFS= read -r -d '' jar_file; do
        jar_files+=("$jar_file")
    done < <(find "$APP_HOME" -maxdepth 1 -mindepth 1 -name "*.jar" -type f -print0 2>/dev/null)
    
    if [ ${#jar_files[@]} -eq 0 ]; then
        print_warning "未在 $APP_HOME 目录中找到JAR文件"
        print_info "请确保JAR文件位于应用根目录中"
        return 1
    fi
    
    print_success "检测到 ${#jar_files[@]} 个JAR文件"
    
    # 更新全局数组
    DETECTED_JAR_FILES=("${jar_files[@]}")
    
    return 0
}

# 从JAR文件的MANIFEST.MF中提取Main-Class
extract_main_class_from_jar() {
    local jar_path="$1"
    
    if [ ! -f "$jar_path" ]; then
        return 1
    fi
    
    # 使用unzip -p读取MANIFEST.MF内容，然后提取Main-Class
    local main_class
    main_class=$(unzip -p "$jar_path" META-INF/MANIFEST.MF 2>/dev/null | \
                grep -i "^Main-Class:" | \
                sed 's/^Main-Class:[[:space:]]*//' | \
                tr -d '\r\n' | \
                sed 's/[[:space:]]*$//')
    
    if [ -n "$main_class" ]; then
        echo "$main_class"
        return 0
    fi
    
    return 1
}

# 解析JAR文件名获取应用名和版本
parse_jar_name() {
    local jar_path="$1"
    local jar_name=$(basename "$jar_path" .jar)
    
    # 优先匹配完整的版本号格式，包括 SNAPSHOT 和 RELEASE
    # 匹配格式: name-version-SNAPSHOT.jar 或 name-vversion-SNAPSHOT.jar
    if [[ "$jar_name" =~ ^(.+)-([0-9]+\.[0-9]+.*-SNAPSHOT)$ ]]; then
        echo "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$jar_name" =~ ^(.+)-(v[0-9]+\.[0-9]+.*-SNAPSHOT)$ ]]; then
        echo "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$jar_name" =~ ^(.+)-([0-9]+\.[0-9]+.*-RELEASE)$ ]]; then
        echo "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$jar_name" =~ ^(.+)-(v[0-9]+\.[0-9]+.*-RELEASE)$ ]]; then
        echo "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    # 匹配普通版本号格式
    elif [[ "$jar_name" =~ ^(.+)-([0-9]+\.[0-9]+.*)$ ]]; then
        echo "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$jar_name" =~ ^(.+)-(v[0-9]+\.[0-9]+.*)$ ]]; then
        echo "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    # 兜底匹配 SNAPSHOT 或 RELEASE
    elif [[ "$jar_name" =~ ^(.+)-(SNAPSHOT|RELEASE)$ ]]; then
        echo "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        echo "$jar_name" ""
    fi
}

# 选择JAR文件
select_jar_file() {
    detect_jar_files
    
    if [ $? -ne 0 ]; then
        print_error "未找到JAR文件，请确保JAR文件位于 $APP_HOME 目录中" >&2
        return 1
    fi
    
    # 使用全局数组
    local jar_files=("${DETECTED_JAR_FILES[@]}")
    
    if [ ${#jar_files[@]} -eq 1 ]; then
        print_info "自动选择唯一的JAR文件: $(basename "${jar_files[0]}")" >&2
        echo "${jar_files[0]}"
        return 0
    fi
    
    echo "" >&2
    echo "请您选择要配置的应用：" >&2
    echo "----------------------------------------" >&2
    
    for i in "${!jar_files[@]}"; do
        local jar_name=$(basename "${jar_files[$i]}")
        echo "    $((i+1)): $jar_name" >&2
    done
    
    echo "----------------------------------------" >&2
    echo "" >&2
    while true; do
        echo -n "请输入序号 (1-${#jar_files[@]}): " >&2
        read choice
        
        # 检查输入是否为空
        if [ -z "$choice" ]; then
            print_error "输入不能为空，请重新选择" >&2
            continue
        fi
        
        # 检查输入是否为数字
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            print_error "请输入数字，不是文字" >&2
            continue
        fi
        
        # 检查数字范围
        if [ "$choice" -ge 1 ] && [ "$choice" -le ${#jar_files[@]} ]; then
            local selected_jar="${jar_files[$((choice-1))]}"
            echo "" >&2
            print_success "已选择: $(basename "$selected_jar")" >&2
            echo "$selected_jar"
            return 0
        else
            print_error "序号超出范围，请输入 1-${#jar_files[@]} 之间的数字" >&2
        fi
    done
}

# 配置应用信息
configure_app_info() {
    local selected_jar
    selected_jar=$(select_jar_file)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 解析JAR文件名
    local parsed_info
    parsed_info=($(parse_jar_name "$selected_jar"))
    local suggested_name="${parsed_info[0]}"
    local suggested_version="${parsed_info[1]}"
    
    echo ""
    print_info "配置应用信息"
    echo "----------------------------------------"
    
    # 配置应用名称
    if [ -n "$suggested_name" ]; then
        read -p "应用名称 [默认: $suggested_name]: " app_name
        app_name=${app_name:-$suggested_name}
    else
        while true; do
            read -p "应用名称: " app_name
            if [ -n "$app_name" ]; then
                break
            else
                print_error "应用名称不能为空"
            fi
        done
    fi
    
    # 配置应用版本
    if [ -n "$suggested_version" ]; then
        read -p "应用版本 [默认: $suggested_version]: " app_version
        app_version=${app_version:-$suggested_version}
    else
        read -p "应用版本 [可选]: " app_version
    fi
    
    # 全局变量赋值
    APP_NAME="$app_name"
    APP_VERSION="$app_version"
    
    # 检测和配置Main-Class
    configure_main_class "$selected_jar"
    
    print_success "应用信息配置完成"
    print_info "应用名称: $APP_NAME"
    if [ -n "$APP_VERSION" ]; then
        print_info "应用版本: $APP_VERSION"
    else
        print_info "应用版本: 未设置"
    fi
    if [ -n "$MAIN_CLASS" ]; then
        print_info "主类: $MAIN_CLASS"
    fi
}

# 配置Main-Class
configure_main_class() {
    local jar_path="$1"
    
    echo ""
    print_info "检测应用主类"
    echo "----------------------------------------"
    
    # 尝试从JAR文件中提取Main-Class
    local detected_main_class
    detected_main_class=$(extract_main_class_from_jar "$jar_path")
    
    if [ -n "$detected_main_class" ]; then
        print_success "自动检测到主类: $detected_main_class"
        read -p "是否使用检测到的主类? (y/n) [默认: y]: " use_detected
        use_detected=${use_detected:-y}
        
        case "$use_detected" in
            [Yy]|[Yy][Ee][Ss])
                MAIN_CLASS="$detected_main_class"
                print_success "使用检测到的主类: $MAIN_CLASS"
                return 0
                ;;
            [Nn]|[Nn][Oo])
                print_info "将手动输入主类"
                ;;
            *)
                print_error "无效输入，将使用检测到的主类"
                MAIN_CLASS="$detected_main_class"
                return 0
                ;;
        esac
    else
        print_warning "无法从JAR文件中检测到主类"
        print_info "对于Thin JAR，通常可以直接使用 -jar 启动，无需指定主类"
        print_info "如果启动时出现 '找不到主类' 错误，可以重新运行setup.sh手动指定"
        
        read -p "是否手动指定主类? (y/n) [默认: n]: " specify_main_class
        specify_main_class=${specify_main_class:-n}
        
        case "$specify_main_class" in
            [Yy]|[Yy][Ee][Ss])
                print_info "请手动输入主类"
                ;;
            *)
                print_info "跳过主类配置，将使用JAR文件的MANIFEST.MF"
                MAIN_CLASS=""
                return 0
                ;;
        esac
    fi
    
    # 手动输入主类
    while true; do
        read -p "请输入应用主类 [如: com.yourcompany.yourapp.Application]: " main_class
        
        if [ -n "$main_class" ]; then
            # 简单验证主类格式（包含包名的Java类名）
            if [[ "$main_class" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)*$ ]]; then
                MAIN_CLASS="$main_class"
                print_success "主类设置为: $MAIN_CLASS"
                break
            else
                print_error "主类格式不正确，请输入完整的Java类名（如: com.yourcompany.yourapp.Application）"
            fi
        else
            print_warning "主类为空，将使用JAR文件的MANIFEST.MF"
            MAIN_CLASS=""
            break
        fi
    done
}

# 配置实例数量
configure_instances() {
    echo ""
    print_info "配置应用实例"
    echo "----------------------------------------"
    
    while true; do
        read -p "请输入要创建的实例数量 [默认: 1, 最大: 3]: " instance_count
        instance_count=${instance_count:-1}
        
        if [[ "$instance_count" =~ ^[1-3]$ ]]; then
            break
        else
            print_error "实例数量必须是 1-3 之间的数字"
        fi
    done
    
    INSTANCE_COUNT=$instance_count
    print_success "实例数量设置为: $INSTANCE_COUNT"
    
    # 如果实例数量大于1，配置多实例
    if [ "$INSTANCE_COUNT" -gt 1 ]; then
        configure_multi_instances
    fi
}

# 扫描Spring配置文件中的profiles
scan_spring_profiles() {
    local config_dir="$1"
    local profiles=()
    
    if [ ! -d "$config_dir" ]; then
        return 1
    fi
    
    # 扫描 application*.properties 文件
    for file in "$config_dir"/application*.properties; do
        [ -f "$file" ] || continue
        
        # 提取文件名中的profile
        local filename=$(basename "$file")
        if [[ "$filename" =~ ^application-([^.]+)\.properties$ ]]; then
            local profile="${BASH_REMATCH[1]}"
            # 避免重复添加
            if [[ ! " ${profiles[*]} " =~ " ${profile} " ]]; then
                profiles+=("$profile")
            fi
        fi
    done
    
    # 扫描 application*.yml 和 application*.yaml 文件
    for ext in yml yaml; do
        for file in "$config_dir"/application*."$ext"; do
            [ -f "$file" ] || continue
            
            # 提取文件名中的profile
            local filename=$(basename "$file")
            if [[ "$filename" =~ ^application-([^.]+)\.$ext$ ]]; then
                local profile="${BASH_REMATCH[1]}"
                # 避免重复添加
                if [[ ! " ${profiles[*]} " =~ " ${profile} " ]]; then
                    profiles+=("$profile")
                fi
            fi
        done
    done
    
    # 输出找到的profiles
    printf '%s\n' "${profiles[@]}"
    return 0
}

# 配置Spring Profiles
configure_spring_profiles() {
    echo ""
    print_info "配置Spring Profiles"
    echo "----------------------------------------"
    
    # 扫描appconfig目录
    local config_dir="$APP_HOME/appconfig"
    local available_profiles
    
    print_info "扫描配置目录: $config_dir"
    
    if [ ! -d "$config_dir" ]; then
        print_warning "配置目录不存在: $config_dir"
        print_info "将使用默认profile: default"
        SPRING_PROFILES_ACTIVE="default"
        return 0
    fi
    
    # 获取可用的profiles
    available_profiles=($(scan_spring_profiles "$config_dir"))
    
    if [ ${#available_profiles[@]} -eq 0 ]; then
        print_warning "未找到任何Spring profile配置文件"
        print_info "将使用默认profile: default"
        SPRING_PROFILES_ACTIVE="default"
        return 0
    fi
    
    # 显示可用的profiles
    echo ""
    print_success "找到以下Spring Profiles:"
    echo "  0) default (默认profile)"
    
    local i=1
    for profile in "${available_profiles[@]}"; do
        echo "  $i) $profile"
        ((i++))
    done
    
    echo ""
    
    # 用户选择profile
    while true; do
        read -p "请选择要使用的Spring Profile [默认: 0]: " profile_choice
        profile_choice=${profile_choice:-0}
        
        # 验证输入
        if [[ "$profile_choice" =~ ^[0-9]+$ ]]; then
            if [ "$profile_choice" -eq 0 ]; then
                SPRING_PROFILES_ACTIVE="default"
                print_success "选择了默认profile: default"
                break
            elif [ "$profile_choice" -ge 1 ] && [ "$profile_choice" -le ${#available_profiles[@]} ]; then
                local selected_index=$((profile_choice - 1))
                SPRING_PROFILES_ACTIVE="${available_profiles[$selected_index]}"
                print_success "选择了profile: $SPRING_PROFILES_ACTIVE"
                break
            else
                print_error "无效选择，请输入 0-${#available_profiles[@]} 之间的数字"
            fi
        else
            print_error "请输入有效的数字"
        fi
    done
    
    # 显示选择的配置文件
    echo ""
    print_info "将查找以下配置文件:"
    echo "  - application.properties/yml/yaml (通用配置)"
    if [ "$SPRING_PROFILES_ACTIVE" != "default" ]; then
        echo "  - application-${SPRING_PROFILES_ACTIVE}.properties/yml/yaml (profile配置)"
    fi
}

# 配置JVM内存参数
configure_jvm_memory() {
    echo ""
    print_info "配置JVM内存参数"
    echo "----------------------------------------"
    
    # 配置初始堆内存
    while true; do
        read -p "请输入JVM初始堆内存大小 [默认: 2g]: " jvm_xms
        jvm_xms=${jvm_xms:-2g}
        
        # 验证内存格式 (支持 m, M, g, G 后缀)
        if [[ "$jvm_xms" =~ ^[0-9]+[mMgG]?$ ]]; then
            # 如果没有单位，默认添加m
            if [[ "$jvm_xms" =~ ^[0-9]+$ ]]; then
                jvm_xms="${jvm_xms}m"
            fi
            break
        else
            print_error "内存格式不正确，请输入数字加单位，如: 512m, 2g"
        fi
    done
    
    # 配置最大堆内存
    while true; do
        read -p "请输入JVM最大堆内存大小 [默认: 4g]: " jvm_xmx
        jvm_xmx=${jvm_xmx:-4g}
        
        # 验证内存格式
        if [[ "$jvm_xmx" =~ ^[0-9]+[mMgG]?$ ]]; then
            # 如果没有单位，默认添加m
            if [[ "$jvm_xmx" =~ ^[0-9]+$ ]]; then
                jvm_xmx="${jvm_xmx}m"
            fi
            break
        else
            print_error "内存格式不正确，请输入数字加单位，如: 512m, 2g"
        fi
    done
    
    # 验证最大内存不小于初始内存
    local xms_value=$(echo "$jvm_xms" | sed 's/[mMgG]$//')
    local xmx_value=$(echo "$jvm_xmx" | sed 's/[mMgG]$//')
    local xms_unit=$(echo "$jvm_xms" | sed 's/^[0-9]*//' | tr '[:upper:]' '[:lower:]')
    local xmx_unit=$(echo "$jvm_xmx" | sed 's/^[0-9]*//' | tr '[:upper:]' '[:lower:]')
    
    # 转换为MB进行比较
    local xms_mb=$xms_value
    local xmx_mb=$xmx_value
    
    if [ "$xms_unit" = "g" ]; then
        xms_mb=$((xms_value * 1024))
    fi
    
    if [ "$xmx_unit" = "g" ]; then
        xmx_mb=$((xmx_value * 1024))
    fi
    
    if [ "$xmx_mb" -lt "$xms_mb" ]; then
        print_warning "最大堆内存($jvm_xmx)小于初始堆内存($jvm_xms)，将自动调整最大堆内存为初始堆内存大小"
        jvm_xmx="$jvm_xms"
    fi
    
    # 全局变量赋值
    JVM_XMS="$jvm_xms"
    JVM_XMX="$jvm_xmx"
    
    print_success "JVM内存配置完成"
    print_info "初始堆内存: $JVM_XMS"
    print_info "最大堆内存: $JVM_XMX"
}

# 配置多实例
configure_multi_instances() {
    echo ""
    print_info "配置多实例部署"
    echo "----------------------------------------"
    
    # 检查是否存在现有配置
    if [ -f "$SERVERS_CONFIG" ]; then
        print_warning "发现现有的 servers.properties 配置文件"
        while true; do
            read -p "是否覆盖现有配置? (y/n) [默认: n]: " overwrite
            overwrite=${overwrite:-n}
            
            case "$overwrite" in
                [Yy]|[Yy][Ee][Ss])
                    backup_existing_instances
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    print_info "保留现有配置，退出配置向导"
                    return 0
                    ;;
                *)
                    print_error "请输入 y 或 n"
                    ;;
            esac
        done
    fi
    
    # 创建新的多实例配置
    create_servers_properties
}

# 备份现有实例
backup_existing_instances() {
    local backup_dir="$APP_HOME/back"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    print_info "备份现有实例到 $backup_dir"
    
    # 创建备份目录
    mkdir -p "$backup_dir"
    
    # 读取现有配置并备份实例目录
    if [ -f "$SERVERS_CONFIG" ]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            
            # 清理空格
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            
            if [ -n "$value" ] && [ -d "$APP_HOME/$value" ]; then
                local backup_name="${value}_${timestamp}"
                print_info "备份实例目录: $value -> back/$backup_name"
                mv "$APP_HOME/$value" "$backup_dir/$backup_name"
            fi
        done < "$SERVERS_CONFIG"
        
        # 备份配置文件
        cp "$SERVERS_CONFIG" "$backup_dir/servers.properties_${timestamp}"
        print_success "配置文件已备份"
    fi
}

# 创建servers.properties配置
create_servers_properties() {
    local base_port=8080
    
    echo ""
    print_info "创建多实例配置"
    
    # 获取基础端口
    while true; do
        read -p "请输入基础端口号 [默认: $base_port]: " input_port
        input_port=${input_port:-$base_port}
        
        if [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1024 ] && [ "$input_port" -le 65535 ]; then
            base_port=$input_port
            break
        else
            print_error "端口号必须是 1024-65535 之间的数字"
        fi
    done
    
    # 生成servers.properties
    {
        echo "# Spring Boot 多实例配置"
        echo "# 格式: 实例名=实例目录"
        echo "# 实例目录格式: instance-端口号"
        echo "# 生成时间: $(date)"
        echo ""
    } > "$SERVERS_CONFIG"
    
    # 创建实例配置
    for i in $(seq 1 "$INSTANCE_COUNT"); do
        local port=$((base_port + i - 1))
        local instance_name="instance$i"
        local instance_dir="instance-$port"
        
        echo "$instance_name=$instance_dir" >> "$SERVERS_CONFIG"
        
        # 创建实例目录
        local instance_path="$APP_HOME/$instance_dir"
        mkdir -p "$instance_path/logs"
        mkdir -p "$instance_path/appconfig"
        
        print_success "创建实例: $instance_name -> $instance_dir (端口: $port)"
    done
    
    print_success "多实例配置创建完成: $SERVERS_CONFIG"
}

# 生成set-env.sh文件
generate_set_env() {
    if [ -f "$SET_ENV_FILE" ]; then
        print_warning "环境配置文件已存在: $SET_ENV_FILE"
        while true; do
            read -p "是否覆盖现有环境配置? (y/n) [默认: n]: " overwrite
            overwrite=${overwrite:-n}
            
            case "$overwrite" in
                [Yy]|[Yy][Ee][Ss])
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    print_info "保留现有环境配置"
                    return 0
                    ;;
                *)
                    print_error "请输入 y 或 n"
                    ;;
            esac
        done
    fi
    
    print_info "生成环境配置文件: $SET_ENV_FILE"
    
    {
        echo "#!/bin/bash"
        echo "#"
        echo "# Spring Boot 应用环境配置"
        echo "# 由 setup.sh 自动生成于 $(date)"
        echo "#"
        echo "# 注意：这些变量仅在当前脚本作用域内有效，不会污染全局环境"
        echo "#"
        echo ""
        echo "# 应用基本信息"
        echo "APP_NAME=\"$APP_NAME\""
        if [ -n "$APP_VERSION" ]; then
            echo "APP_VERSION=\"$APP_VERSION\""
        else
            echo "APP_VERSION=\"\""
        fi
        echo ""
        echo "# 应用主类"
        if [ -n "$MAIN_CLASS" ]; then
            echo "MAIN_CLASS=\"$MAIN_CLASS\""
        else
            echo "# MAIN_CLASS=\"\" # 未设置主类，Thin JAR将使用MANIFEST.MF中的Main-Class"
        fi
        echo ""
    } > "$SET_ENV_FILE"
    
    chmod +x "$SET_ENV_FILE"
    print_success "环境配置文件生成完成"
}

# 添加Spring Profiles配置到set-env.sh
add_spring_profiles_to_set_env() {
    echo "=> 调试: SPRING_PROFILES_ACTIVE = '$SPRING_PROFILES_ACTIVE'"
    echo "# Spring Profiles 配置" >> "$SET_ENV_FILE"
    if [ -n "$SPRING_PROFILES_ACTIVE" ]; then
        echo "SPRING_PROFILES_ACTIVE=\"$SPRING_PROFILES_ACTIVE\"" >> "$SET_ENV_FILE"
    else
        echo "SPRING_PROFILES_ACTIVE=\"default\"" >> "$SET_ENV_FILE"
    fi
    echo "" >> "$SET_ENV_FILE"
}

# 生成JVM配置文件
generate_jvm_env() {
    if [ -f "$JVM_ENV_FILE" ]; then
        print_warning "JVM配置文件已存在: $JVM_ENV_FILE"
        while true; do
            read -p "是否覆盖现有JVM配置? (y/n) [默认: n]: " overwrite
            overwrite=${overwrite:-n}
            
            case "$overwrite" in
                [Yy]|[Yy][Ee][Ss])
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    print_info "保留现有JVM配置"
                    return 0
                    ;;
                *)
                    print_error "请输入 y 或 n"
                    ;;
            esac
        done
    fi
    
    print_info "生成JVM配置文件: $JVM_ENV_FILE"
    
    {
        echo "#!/bin/bash"
        echo "#"
        echo "# JVM 参数配置文件"
        echo "# 由 setup.sh 自动生成于 $(date)"
        echo "#"
        echo "# 注意：这些变量仅在当前脚本作用域内有效，不会污染全局环境"
        echo "#"
        echo ""
        echo "# 堆内存配置"
        echo "JVM_XMS=\"${JVM_XMS:-2g}\""
        echo "JVM_XMX=\"${JVM_XMX:-4g}\""
        echo ""
        echo "# Metaspace 配置"
        echo "JVM_METASPACE_SIZE=\"128m\""
        echo "JVM_MAX_METASPACE_SIZE=\"512m\""
        echo ""
        echo "# GC 配置"
        echo "JVM_MAX_GC_PAUSE_MS=\"200\""
        echo "JVM_IHOP=\"45\""
        echo ""
        echo "# GC 日志配置"
        echo "JVM_GC_LOG_FILESIZE=\"20M\""
        echo "JVM_GC_LOG_FILECOUNT=\"5\""
        echo ""
        echo "# 线程栈大小 (可选)"
        echo "JVM_THREAD_STACK_SIZE=\"\""
        echo ""
        echo "# 错误处理"
        echo "JVM_HEAP_DUMP_PATH=\"\${LOG_DIR}/heapdump.hprof\""
        echo "JVM_ERROR_FILE=\"\${LOG_DIR}/hs_err_pid%p.log\""
        echo ""
        echo "# 额外的JVM参数"
        echo "EXTRA_JAVA_OPTS=\"\""
        echo ""
    } > "$JVM_ENV_FILE"
    
    chmod +x "$JVM_ENV_FILE"
    print_success "JVM配置文件生成完成"
}

# 生成优雅停止配置文件
generate_shutdown_env() {
    if [ -f "$SHUTDOWN_ENV_FILE" ]; then
        print_warning "优雅停止配置文件已存在: $SHUTDOWN_ENV_FILE"
        while true; do
            read -p "是否覆盖现有优雅停止配置? (y/n) [默认: n]: " overwrite
            overwrite=${overwrite:-n}
            
            case "$overwrite" in
                [Yy]|[Yy][Ee][Ss])
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    print_info "保留现有优雅停止配置"
                    return 0
                    ;;
                *)
                    print_error "请输入 y 或 n"
                    ;;
            esac
        done
    fi
    
    print_info "生成优雅停止配置文件: $SHUTDOWN_ENV_FILE"
    
    {
        echo "#!/bin/bash"
        echo "#"
        echo "# 优雅停止配置文件"
        echo "# 由 setup.sh 自动生成于 $(date)"
        echo "#"
        echo "# 注意：这些变量仅在当前脚本作用域内有效，不会污染全局环境"
        echo "#"
        echo ""
        echo "# 优雅停止等待时间（秒）"
        echo "GRACEFUL_SHUTDOWN_TIMEOUT=\"30\""
        echo ""
        echo "# 强制终止等待时间（秒）"
        echo "FORCE_KILL_TIMEOUT=\"10\""
        echo ""
        echo "# 是否启用Actuator shutdown端点"
        echo "ENABLE_ACTUATOR_SHUTDOWN=\"false\""
        echo ""
        echo "# Actuator端口"
        echo "ACTUATOR_SHUTDOWN_PORT=\"8080\""
        echo ""
        echo "# Actuator shutdown超时时间（秒）"
        echo "ACTUATOR_SHUTDOWN_TIMEOUT=\"5\""
        echo ""
    } > "$SHUTDOWN_ENV_FILE"
    
    chmod +x "$SHUTDOWN_ENV_FILE"
    print_success "优雅停止配置文件生成完成"
}

# 显示配置摘要
show_summary() {
    echo ""
    echo "========================================"
    echo "  配置完成摘要"
    echo "========================================"
    echo ""
    print_success "应用名称: $APP_NAME"
    if [ -n "$APP_VERSION" ]; then
        print_success "应用版本: $APP_VERSION"
    else
        print_success "应用版本: 未设置"
    fi
    print_success "实例数量: $INSTANCE_COUNT"
    
    # 显示JVM内存配置
    if [ -n "$JVM_XMS" ] && [ -n "$JVM_XMX" ]; then
        echo ""
        print_info "JVM内存配置:"
        echo "  - 初始堆内存: $JVM_XMS"
        echo "  - 最大堆内存: $JVM_XMX"
    fi
    
    if [ "$INSTANCE_COUNT" -gt 1 ]; then
        echo ""
        print_info "多实例配置:"
        if [ -f "$SERVERS_CONFIG" ]; then
            while IFS='=' read -r key value; do
                [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
                key="${key#"${key%%[![:space:]]*}"}"
                key="${key%"${key##*[![:space:]]}"}"
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                
                # 提取端口号
                if [[ "$value" =~ -([0-9]+)$ ]]; then
                    local port="${BASH_REMATCH[1]}"
                    echo "  - $key -> $value (端口: $port)"
                else
                    echo "  - $key -> $value"
                fi
            done < "$SERVERS_CONFIG"
        fi
    fi
    
    echo ""
    print_info "生成的配置文件:"
    echo "  - $SET_ENV_FILE"
    echo "  - $JVM_ENV_FILE"
    echo "  - $SHUTDOWN_ENV_FILE"
    if [ "$INSTANCE_COUNT" -gt 1 ]; then
        echo "  - $SERVERS_CONFIG"
    fi
    
    echo ""
    print_info "使用方法:"
    echo "  1. 启动应用: ./startup.sh start"
    echo "  2. 停止应用: ./startup.sh stop"
    echo "  3. 重启应用: ./startup.sh restart"
    echo "  4. 查看状态: ./startup.sh status"
    
    if [ "$INSTANCE_COUNT" -gt 1 ]; then
        echo ""
        print_info "多实例操作:"
        echo "  - 操作所有实例: ./startup.sh start all"
        echo "  - 操作单个实例: ./startup.sh start instance1"
    fi
}

# 主函数
main() {
    show_welcome
    
    # 配置应用信息
    if ! configure_app_info; then
        print_error "应用信息配置失败"
        exit 1
    fi
    
    # 配置实例
    configure_instances
    
    # 配置Spring Profiles
    configure_spring_profiles
    
    # 配置JVM内存参数
    configure_jvm_memory
    
    # 生成配置文件
    generate_set_env
    add_spring_profiles_to_set_env
    generate_jvm_env
    generate_shutdown_env
    
    # 显示摘要
    show_summary
    
    echo ""
    print_success "Spring Boot 应用部署配置完成!"
}

# 运行主函数
main "$@"