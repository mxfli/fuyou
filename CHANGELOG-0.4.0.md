# v0.4.0 变更日志

> 发布日期: 2025-11-23 | 提交范围: 67daef83..a009eab

## 📦 新增功能

### 🚀 本地部署自动化脚本

- 新增 `deploy.sh` 实现 Spring Boot 项目一键构建和部署
- 支持 IDE 环境变量、`.fuyou` 配置文件、脚本硬编码三种配置方式
- 提供 `--init` 参数交互式初始化部署配置
- 智能验证部署目录的有效性和安全性
- 自动 Maven 构建并同步 appconfig、lib、JAR 文件
- 支持多子项目独立配置，互不干扰

### 📊 CSV 大文件分割工具

- 新增 `csv_file_splitter.sh` 处理大型 CSV 文件
- 按 100 万行自动分割，智能保留标题行
- 支持单文件和批量处理两种模式
- 流式处理优化内存，支持 GB 级超大文件
- 自动检测文件大小，跳过无需分割的文件

### 🎯 配置向导优化

- `setup.sh` JAR 文件按修改时间倒序排列
- 优先显示最新构建的 JAR 文件
- 兼容 `stat` 和 `ls` 两种检测方式
- 优化用户提示信息

## 📝 文档更新

### 新增文档

- **DEPLOY.md** - 本地部署脚本完整使用指南 (180+ 行)
- **CHANGELOG-deploy.md** - 部署功能变更日志
- **DEPLOY-TEST-SUMMARY.md** - 部署脚本测试报告
- **USAGE-NOTE.md** - 部署脚本使用要点
- **examples/README.md** - 配置示例说明
- **RELEASE-NOTES-0.4.0.md** - 详细发布说明 (316 行)

### 更新文档

- **README.md** - 更新 v0.4.0 版本说明和功能介绍

### 示例文件

- **examples/.fuyou.example** - 部署配置文件模板
- **examples/.gitignore.example** - Git 忽略文件示例
- **examples/quick-start.sh** - 快速开始脚本

## 📊 统计数据

- **提交数量**: 3 个
- **文件变更**: 12 个文件 (11 新增, 1 修改)
- **代码行数**: +2000/-16 (净增 ~1986 行)
- **文档行数**: +500 行文档

## 🔗 提交记录

```
a009eab - feat(deploy): 增加通用本地部署脚本，支持自动化构建和本地同步部署
9110824 - feat(setup): 优化 JAR 文件检测逻辑，支持按修改时间倒序排列并更新提示信息
8d0add5 - feat(setup): 优化 JAR 文件检测逻辑，支持按修改时间倒序排列并更新提示信息
```

## 🎯 主要变更文件

### 核心脚本

- `spring-boot-shell-manager/deploy.sh` (+240 行) - 本地部署脚本
- `spring-boot-shell-manager/setup.sh` (+19/-5 行) - 优化 JAR 检测
- `csv-fie-splitter/csv_file_splitter.sh` (+150 行) - CSV 分割工具

### 文档和示例

- `spring-boot-shell-manager/DEPLOY.md` (+180 行) - 部署指南
- `spring-boot-shell-manager/CHANGELOG-deploy.md` (+265 行) - 变更日志
- `spring-boot-shell-manager/DEPLOY-TEST-SUMMARY.md` (+272 行) - 测试报告
- `spring-boot-shell-manager/examples/` - 新增配置示例目录

## 🔄 升级说明

### 兼容性

- ✅ 完全向后兼容 v0.3.0
- ✅ 不影响现有功能
- ✅ 新增功能为可选模块

### 升级步骤

```bash
# 1. 更新代码
git pull origin release/0.4.0

# 2. (可选) 初始化本地部署配置
cd spring-boot-shell-manager
./deploy.sh --init /path/to/deploy

# 3. (可选) 添加 .fuyou 到 .gitignore
echo ".fuyou" >> .gitignore
```

## 📚 相关文档

- [README.md](README.md) - 项目总览
- [RELEASE-NOTES-0.4.0.md](RELEASE-NOTES-0.4.0.md) - 详细发布说明
- [spring-boot-shell-manager/DEPLOY.md](spring-boot-shell-manager/DEPLOY.md) - 部署指南
- [spring-boot-shell-manager/MANUAL.md](spring-boot-shell-manager/MANUAL.md) - 使用手册

---

**下一版本**: v0.5.0 (规划中)
