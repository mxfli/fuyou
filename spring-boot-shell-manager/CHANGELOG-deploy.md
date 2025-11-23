# Deploy Script 功能更新日志

## 🎉 版本更新：添加通用本地部署功能

**更新日期**: 2025-11-23

### 📦 新增功能

#### 1. 通用本地部署脚本 (`deploy.sh`)

将原本硬编码的本地部署脚本改造为通用工具，支持多种配置方式：

**核心特性：**

- ✅ 支持三种配置方式（环境变量、配置文件、脚本硬编码）
- ✅ 交互式初始化（`--init` 参数）
- ✅ 自动检测部署目录有效性
- ✅ Maven 自动构建和同步
- ✅ 智能 JAR 版本管理（自动清理旧版本）

**配置优先级：**

1. IDE 环境变量 `DEPLOY_DIR`（最高优先级）
2. 配置文件 `.fuyou`
3. 脚本内硬编码（已移除，不推荐）

#### 2. 新增配置文件 `.fuyou`

在项目根目录自动生成的部署配置文件：

```bash
# Spring Boot 本地部署配置
# 由 deploy.sh --init 自动生成

# 部署目标目录（必须是绝对路径）
DEPLOY_DIR="/path/to/deploy"
```

**特点：**

- 通过 `deploy.sh --init` 自动生成
- 建议加入 `.gitignore`（每个开发者维护自己的配置）
- 支持绝对路径

### 📝 文档更新

#### 新增文档

1. **`DEPLOY.md`** - 部署脚本完整使用指南
    - 快速开始
    - 配置方式详解
    - 部署流程说明
    - 使用场景
    - 故障排除
    - 最佳实践
    - 常见问题

2. **`examples/README.md`** - 配置示例说明
    - 目录结构
    - 配置文件说明
    - 使用场景示例
    - 最佳实践

3. **`examples/.fuyou.example`** - 部署配置示例模板

4. **`examples/.gitignore.example`** - Git 忽略文件示例

5. **`CHANGELOG-deploy.md`** - 本变更日志

#### 更新文档

1. **`README.md`** - 主文档
    - 添加本地自动化部署章节
    - 更新目录结构说明（区分开发阶段和部署后）
    - 添加 `.fuyou` 配置文件说明
    - 更新最佳实践（添加开发阶段工作流程）
    - 添加部署脚本到核心特性列表

### 🔧 脚本功能详解

#### `deploy.sh` 命令行参数

```bash
# 显示帮助信息
./deploy.sh --help
./deploy.sh -h

# 初始化部署配置
./deploy.sh --init /path/to/deploy
./deploy.sh -i /path/to/deploy

# 执行部署（使用配置文件）
./deploy.sh

# 执行部署（使用环境变量）
DEPLOY_DIR=/path/to/deploy ./deploy.sh
```

#### 部署流程

1. **配置检查**
    - 检查是否配置了 `DEPLOY_DIR`
    - 验证部署目录是否存在
    - 目录不存在时报错（不自动创建）

2. **Maven 构建**
   ```bash
   mvn clean compile package -DskipTests -T1C -U
   ```
    - 清理旧构建产物
    - 编译和打包
    - 跳过测试（加快速度）
    - 并行构建
    - 强制更新快照依赖

3. **同步配置和依赖**
    - 同步 `target/appconfig/` → `$DEPLOY_DIR/appconfig/`
    - 同步 `target/lib/` → `$DEPLOY_DIR/lib/`（Thin JAR）
    - 使用 `rsync --delete` 确保一致性

4. **更新 JAR 文件**
    - 自动查找新构建的 JAR
    - 提取 artifact 前缀
    - 删除部署目录中的旧版本
    - 复制新版本到部署目录

### 🎯 使用场景

#### 场景 1: 开发环境快速部署

```bash
# 首次配置
./spring-boot-shell-manager/deploy.sh --init ~/deploy/dev

# 开发迭代
# 修改代码...
./spring-boot-shell-manager/deploy.sh

# 快速测试
cd ~/deploy/dev
./spring-boot-shell-manager/startup.sh restart
```

#### 场景 2: IDE 集成

**IntelliJ IDEA:**

- Run → Edit Configurations
- 添加 Shell Script
- Script path: `spring-boot-shell-manager/deploy.sh`
- Environment: `DEPLOY_DIR=/path/to/deploy`

**VS Code:**

- 在 `.vscode/tasks.json` 中配置任务
- 快捷键一键部署

#### 场景 3: 多环境部署

```bash
# 开发环境
DEPLOY_DIR=~/deploy/dev ./spring-boot-shell-manager/deploy.sh

# 测试环境
DEPLOY_DIR=~/deploy/test ./spring-boot-shell-manager/deploy.sh

# 生产模拟
DEPLOY_DIR=~/deploy/prod ./spring-boot-shell-manager/deploy.sh
```

### ⚠️ 注意事项

1. **部署目录必须预先存在**
    - 脚本不会自动创建目录
    - 目录不存在时会报错并提示

2. **配置文件建议加入 .gitignore**
   ```bash
   echo ".fuyou" >> .gitignore
   ```

3. **环境变量优先级**
    - IDE/终端环境变量 > 配置文件 > 脚本硬编码
    - 便于灵活切换部署目标

4. **Maven 构建失败处理**
    - 构建失败时立即终止
    - 不会执行后续的同步和部署操作

### 🔄 迁移指南

#### 从旧版本迁移

如果之前使用硬编码的 `DEPLOY_DIR`：

**旧方式（不推荐）：**

```bash
# 直接编辑脚本
DEPLOY_DIR="/path/to/deploy"  # 硬编码
```

**新方式（推荐）：**

```bash
# 方式1: 使用配置文件
./spring-boot-shell-manager/deploy.sh --init /path/to/deploy

# 方式2: 使用 IDE 环境变量
# 在 IDE 中配置 DEPLOY_DIR 环境变量
```

#### 团队协作建议

1. **将管理器脚本纳入版本控制**
   ```bash
   git add spring-boot-shell-manager/
   ```

2. **配置文件不纳入版本控制**
   ```bash
   echo ".fuyou" >> .gitignore
   git commit -m "Add deploy script to gitignore"
   ```

3. **提供配置示例**
   ```bash
   # 团队成员参考示例配置
   cp examples/.fuyou.example .fuyou
   vi .fuyou  # 修改为自己的路径
   ```

### 📊 改进总结

| 特性     | 旧版本    | 新版本             |
|--------|--------|-----------------|
| 部署目录配置 | 硬编码    | 支持环境变量、配置文件     |
| 初始化方式  | 手动编辑脚本 | `--init` 命令自动生成 |
| 目录检查   | 自动创建   | 检查存在性，不自动创建     |
| 帮助信息   | 无      | `--help` 详细说明   |
| 通用性    | 项目特定   | 完全通用            |
| 文档     | 无      | 完整的使用指南         |
| 错误提示   | 简单     | 详细且有建议          |

### 🚀 后续计划

- [ ] 支持 Gradle 项目
- [ ] 添加部署前钩子（pre-deploy hook）
- [ ] 添加部署后钩子（post-deploy hook）
- [ ] 支持远程部署（SSH/rsync）
- [ ] 部署历史记录
- [ ] 回滚功能
- [ ] 并行多环境部署

### 📞 反馈与建议

如有问题或建议，请通过以下方式反馈：

- 提交 Issue
- 提交 Pull Request
- 联系维护者

---

**版权所有** © 2025
