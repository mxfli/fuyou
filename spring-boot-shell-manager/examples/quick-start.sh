#!/bin/bash
# Spring Boot Shell Manager - 快速开始示例脚本
# 此脚本演示如何使用 deploy.sh 进行本地部署

set -e

echo "=========================================="
echo "Spring Boot Shell Manager 快速开始示例"
echo "=========================================="
echo ""

# 检查是否在正确的目录
if [ ! -f "pom.xml" ]; then
  echo "❌ 错误: 请在 Spring Boot 项目根目录执行此脚本"
  echo "💡 提示: cd your-spring-boot-project && ./spring-boot-shell-manager/examples/quick-start.sh"
  exit 1
fi

echo "📋 步骤 1: 配置部署目录"
echo "----------------------------------------"
echo "请输入部署目录路径（必须已存在）："
read -r DEPLOY_PATH

if [ -z "$DEPLOY_PATH" ]; then
  echo "❌ 错误: 部署路径不能为空"
  exit 1
fi

if [ ! -d "$DEPLOY_PATH" ]; then
  echo "⚠️  部署目录不存在: $DEPLOY_PATH"
  echo "是否创建该目录? (y/n)"
  read -r CREATE_DIR
  if [ "$CREATE_DIR" = "y" ] || [ "$CREATE_DIR" = "Y" ]; then
    mkdir -p "$DEPLOY_PATH"
    echo "✅ 已创建目录: $DEPLOY_PATH"
  else
    echo "❌ 已取消"
    exit 1
  fi
fi

echo ""
echo "📋 步骤 2: 初始化部署配置"
echo "----------------------------------------"
./spring-boot-shell-manager/deploy.sh --init "$DEPLOY_PATH"

echo ""
echo "📋 步骤 3: 执行构建和部署"
echo "----------------------------------------"
echo "是否立即执行部署? (y/n)"
read -r DO_DEPLOY

if [ "$DO_DEPLOY" = "y" ] || [ "$DO_DEPLOY" = "Y" ]; then
  ./spring-boot-shell-manager/deploy.sh
  echo ""
  echo "✅ 部署完成！"
  echo ""
  echo "📋 步骤 4: 配置运行环境（可选）"
  echo "----------------------------------------"
  echo "如需配置运行环境，请执行："
  echo "  cd $DEPLOY_PATH"
  echo "  ./spring-boot-shell-manager/setup.sh"
  echo ""
  echo "📋 步骤 5: 启动应用（可选）"
  echo "----------------------------------------"
  echo "配置完成后，可以启动应用："
  echo "  cd $DEPLOY_PATH"
  echo "  ./spring-boot-shell-manager/startup.sh start"
else
  echo ""
  echo "💡 后续可以随时执行部署："
  echo "  ./spring-boot-shell-manager/deploy.sh"
fi

echo ""
echo "=========================================="
echo "✅ 快速开始完成！"
echo "=========================================="
echo ""
echo "📚 更多信息请参考："
echo "  - README.md - 主文档"
echo "  - DEPLOY.md - 部署脚本详细指南"
echo "  - examples/README.md - 配置示例说明"
echo ""
