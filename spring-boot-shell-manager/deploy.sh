#!/bin/bash

# Spring Boot 通用本地部署脚本
# 支持通过环境变量、配置文件或命令行参数指定部署目录
set -euo pipefail

# 获取项目根目录（执行 deploy.sh 的当前工作目录）
PROJECT_ROOT="$(pwd)"

# 配置文件路径（与 deploy.sh 在同一目录，即项目根目录）
CONFIG_FILE="$PROJECT_ROOT/.fuyou"

# 显示使用帮助
show_usage() {
  cat << EOF
📦 Spring Boot 本地部署脚本

用法:
  $0 [选项]

选项:
  -i, --init <目录>    初始化部署配置，设置部署目录到 .fuyou 文件
  -h, --help          显示此帮助信息

部署目录优先级（从高到低）:
  1. IDE 环境变量: DEPLOY_DIR
  2. 配置文件: .fuyou (通过 -i 或 --init 设置)
  3. 脚本内硬编码: DEPLOY_DIR 变量（需手动修改脚本）

示例:
  # 初始化部署目录
  $0 -i /path/to/deploy

  # 通过 IDE 环境变量部署
  DEPLOY_DIR=/path/to/deploy $0

  # 直接执行（需先配置）
  $0

注意:
  - 部署目录必须已存在，脚本不会自动创建
  - 执行前请确保已配置部署目录

EOF
}

# 初始化配置
init_config() {
  local deploy_dir="$1"
  
  # 检查目录是否存在
  if [ ! -d "$deploy_dir" ]; then
    echo "❌ 错误: 部署目录不存在: $deploy_dir"
    echo "💡 提示: 请先创建该目录，或指定一个已存在的目录"
    exit 1
  fi
  
  # 转换为绝对路径
  deploy_dir="$(cd "$deploy_dir" && pwd)"
  
  # 写入配置文件
  cat > "$CONFIG_FILE" << EOF
# Spring Boot 本地部署配置
# 由 deploy.sh --init 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 部署目标目录（必须是绝对路径）
DEPLOY_DIR="$deploy_dir"
EOF
  
  echo "✅ 部署配置已保存到: $CONFIG_FILE"
  echo "📦 部署目录: $deploy_dir"
  echo ""
  echo "现在可以直接运行 '$0' 进行部署"
  exit 0
}

# 解析命令行参数
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--init)
        if [ -z "${2:-}" ]; then
          echo "❌ 错误: --init 需要指定目录参数"
          show_usage
          exit 1
        fi
        init_config "$2"
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        echo "❌ 错误: 未知选项: $1"
        show_usage
        exit 1
        ;;
    esac
    shift
  done
}

# 获取部署目录
get_deploy_dir() {
  local deploy_dir=""
  local config_source=""
  
  # 优先级1: 环境变量
  if [ -n "${DEPLOY_DIR:-}" ]; then
    deploy_dir="$DEPLOY_DIR"
    config_source="环境变量 DEPLOY_DIR"
  # 优先级2: 配置文件
  elif [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    if [ -n "${DEPLOY_DIR:-}" ]; then
      deploy_dir="$DEPLOY_DIR"
      config_source="配置文件 .fuyou"
    fi
  fi
  
  # 检查是否已配置
  if [ -z "$deploy_dir" ]; then
    echo "❌ 错误: 未配置部署目录" >&2
    echo "" >&2
    show_usage >&2
    return 1
  fi
  
  # 转换为绝对路径（用于后续比较）
  deploy_dir="$(cd "$deploy_dir" 2>/dev/null && pwd || echo "$deploy_dir")"
  
  # 检查是否为当前目录
  local current_dir="$(pwd)"
  if [ "$deploy_dir" = "$current_dir" ] || [ "$deploy_dir" = "$PROJECT_ROOT" ]; then
    echo "❌ 错误: 部署目录不能是当前项目目录" >&2
    echo "   当前目录: $current_dir" >&2
    echo "   部署目录: $deploy_dir" >&2
    echo "💡 提示: 请指定一个不同的部署目录" >&2
    return 1
  fi
  
  # 检查目录是否存在
  if [ ! -d "$deploy_dir" ]; then
    echo "❌ 错误: 部署目录不存在: $deploy_dir" >&2
    echo "💡 提示: 请先创建该目录，或重新配置部署路径" >&2
    return 1
  fi
  
  # 显示配置来源（输出到 stderr，这样不会干扰返回值）
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "📋 部署配置信息" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "配置来源: $config_source" >&2
  echo "部署目录: $deploy_dir" >&2
  echo "项目目录: $PROJECT_ROOT" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "" >&2
  
  # 返回部署目录（输出到 stdout，用于命令替换）
  echo "$deploy_dir"
}

# 主函数
main() {
  # 解析命令行参数
  if [ $# -gt 0 ]; then
    parse_args "$@"
  fi
  
  # 获取部署目录（会显示配置信息）
  if ! DEPLOY_DIR=$(get_deploy_dir); then
    exit 1
  fi
  
  echo "🚀 开始构建和部署..."
  echo ""
  
  # Maven构建（失败则立即退出）
  echo "🛠️  正在执行 Maven 构建..."
  if ! mvn clean compile package -DskipTests -T1C -U; then
    echo ""
    echo "❌ Maven 构建失败，已停止后续步骤。"
    exit 1
  fi
  echo ""
  
  # 同步目录（删除多余文件）
  echo "📁 同步 appconfig 和 lib 到部署目录（含删除）..."
  if [ -d "target/appconfig" ]; then
    mkdir -p "$DEPLOY_DIR/appconfig"
    rsync -a --delete "target/appconfig/" "$DEPLOY_DIR/appconfig/"
    echo "  ✓ appconfig 同步完成"
  fi
  
  if [ -d "target/lib" ]; then
    mkdir -p "$DEPLOY_DIR/lib"
    rsync -a --delete "target/lib/" "$DEPLOY_DIR/lib/"
    echo "  ✓ lib 同步完成"
  fi
  echo ""
  
  # 更新JAR文件（先清理旧版本）
  echo "📦 更新 JAR 文件..."
  JAR_FILE=$(find target -maxdepth 1 -name "*.jar" -not -path "*/lib/*" | head -1)
  if [ -n "$JAR_FILE" ]; then
    NEW_JAR_BASENAME=$(basename "$JAR_FILE")
    ARTIFACT_PREFIX=${NEW_JAR_BASENAME%%-[0-9]*}
    
    # 清理旧版本
    if [ -n "$ARTIFACT_PREFIX" ]; then
      OLD_JARS=$(find "$DEPLOY_DIR" -maxdepth 1 -name "${ARTIFACT_PREFIX}-*.jar" 2>/dev/null || true)
      if [ -n "$OLD_JARS" ]; then
        echo "$OLD_JARS" | while read -r old_jar; do
          rm -f "$old_jar"
          echo "  ✓ 删除旧版本: $(basename "$old_jar")"
        done
      fi
    fi
    
    # 复制新版本
    cp -f "$JAR_FILE" "$DEPLOY_DIR/"
    echo "  ✓ JAR文件已更新: $NEW_JAR_BASENAME"
  else
    echo "  ⚠️  未找到 JAR 文件"
  fi
  echo ""
  
  # 部署完成
  echo "✅ 部署完成！"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 部署路径: $DEPLOY_DIR"
  [ -n "${JAR_FILE:-}" ] && echo "📄 JAR文件: $(basename "$JAR_FILE")"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 执行主函数
main "$@"
