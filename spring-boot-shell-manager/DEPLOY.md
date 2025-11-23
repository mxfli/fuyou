# 本地部署脚本使用指南

## 📦 概述

`deploy.sh` 是一个通用的 Spring Boot 本地部署脚本，用于自动化 Maven 构建和本地目录同步部署。

**重要说明：**

- `deploy.sh` 应该放在 **Spring Boot 项目根目录**（与 `pom.xml` 同级）
- `.fuyou` 配置文件会自动创建在 **项目根目录**（与 `deploy.sh` 同级）
- 多个子项目可以各自拥有独立的 `deploy.sh` 和 `.fuyou` 配置

## 🚀 快速开始

### 1. 初始化部署配置

```bash
# 在 Spring Boot 项目根目录执行（deploy.sh 应该在项目根目录）
./deploy.sh --init /path/to/deploy/directory

# 或者使用子目录中的脚本（从项目根目录执行）
cd /path/to/your/spring-boot-project
./spring-boot-shell-manager/deploy.sh --init /path/to/deploy/directory
```

**目录结构示例：**

```
your-spring-boot-project/          # 当前工作目录
├── pom.xml
├── src/
├── deploy.sh                      # 部署脚本（推荐位置）
└── .fuyou                         # 配置文件（自动生成）
```

**注意：**

- 部署目录必须已存在，脚本不会自动创建
- 如果目录不存在，会报错并提示先创建目录

### 2. 执行部署

配置完成后，可以通过以下方式执行部署：

```bash
# 方式1: 使用配置文件（推荐）
./spring-boot-shell-manager/deploy.sh

# 方式2: 使用环境变量（临时）
DEPLOY_DIR=/path/to/deploy ./spring-boot-shell-manager/deploy.sh
```

## ⚙️ 配置方式

脚本支持三种配置部署目录的方式，优先级从高到低：

### 1. IDE 环境变量（优先级最高）

在 IDE 的 Run Configuration 中设置环境变量：

```
DEPLOY_DIR=/path/to/deploy
```

**适用场景：** IDE 集成、临时部署、不同环境切换

### 2. 配置文件 `.fuyou`（推荐）

通过 `--init` 命令创建配置文件：

```bash
./spring-boot-shell-manager/deploy.sh --init /path/to/deploy
```

会在项目根目录生成 `.fuyou` 文件：

```bash
# Spring Boot 本地部署配置
# 由 deploy.sh --init 自动生成

# 部署目标目录（必须是绝对路径）
DEPLOY_DIR="/path/to/deploy"
```

**适用场景：** 固定部署目录、团队协作（可加入 .gitignore）

### 3. 脚本内硬编码（不推荐）

直接编辑 `deploy.sh` 文件，修改 `DEPLOY_DIR` 变量（已被移除）。

**适用场景：** 特殊定制需求

## 📋 部署流程

脚本执行时会自动完成以下步骤：

### 1. Maven 构建

```bash
mvn clean compile package -DskipTests -T1C -U
```

**参数说明：**

- `clean`: 清理之前的构建产物
- `compile`: 编译源代码
- `package`: 打包成 JAR
- `-DskipTests`: 跳过测试（加快构建速度）
- `-T1C`: 使用 1 个线程每 CPU 核心（并行构建）
- `-U`: 强制更新快照依赖

### 2. 同步配置目录

如果存在 `target/appconfig/` 目录，会同步到部署目录：

```bash
rsync -a --delete target/appconfig/ $DEPLOY_DIR/appconfig/
```

**参数说明：**

- `-a`: 归档模式（保留权限、时间戳等）
- `--delete`: 删除目标目录中多余的文件

### 3. 同步依赖库

如果存在 `target/lib/` 目录（Thin JAR 模式），会同步到部署目录：

```bash
rsync -a --delete target/lib/ $DEPLOY_DIR/lib/
```

### 4. 更新 JAR 文件

- 自动查找 `target/` 目录中的 JAR 文件
- 根据 JAR 文件名提取 artifact 前缀
- 删除部署目录中相同前缀的旧版本 JAR
- 复制新版本 JAR 到部署目录

**示例：**

```
构建产物: target/my-app-1.0.0.jar
部署目录: /deploy/my-app-0.9.0.jar

执行结果:
1. 删除: /deploy/my-app-0.9.0.jar
2. 复制: /deploy/my-app-1.0.0.jar
```

## 💡 使用场景

### 开发环境快速部署

```bash
# 1. 首次配置
./spring-boot-shell-manager/deploy.sh --init ~/deploy/dev

# 2. 开发过程
# 修改代码...
./spring-boot-shell-manager/deploy.sh

# 3. 测试部署结果
cd ~/deploy/dev
./spring-boot-shell-manager/startup.sh start
```

### IDE 集成

#### IntelliJ IDEA

1. 打开 Run → Edit Configurations
2. 添加 Shell Script
3. 配置：
    - Script path: `spring-boot-shell-manager/deploy.sh`
    - Working directory: `$ProjectFileDir$`
    - Environment variables: `DEPLOY_DIR=/path/to/deploy`

#### VS Code

在 `.vscode/tasks.json` 中添加：

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Deploy to Local",
      "type": "shell",
      "command": "./spring-boot-shell-manager/deploy.sh",
      "options": {
        "env": {
          "DEPLOY_DIR": "/path/to/deploy"
        }
      },
      "problemMatcher": []
    }
  ]
}
```

### 多环境部署

```bash
# 开发环境
DEPLOY_DIR=~/deploy/dev ./deploy.sh

# 测试环境
DEPLOY_DIR=~/deploy/test ./deploy.sh

# 生产环境（本地模拟）
DEPLOY_DIR=~/deploy/prod ./deploy.sh
```

### 多项目独立配置

如果你有多个 Spring Boot 子项目，每个项目可以有自己的部署配置：

```bash
# 项目结构
workspace/
├── project-a/
│   ├── pom.xml
│   ├── deploy.sh              # 项目A的部署脚本
│   └── .fuyou                 # 项目A的配置（部署到 /deploy/app-a）
├── project-b/
│   ├── pom.xml
│   ├── deploy.sh              # 项目B的部署脚本
│   └── .fuyou                 # 项目B的配置（部署到 /deploy/app-b）
└── project-c/
    ├── pom.xml
    ├── deploy.sh              # 项目C的部署脚本
    └── .fuyou                 # 项目C的配置（部署到 /deploy/app-c）

# 使用方法
cd workspace/project-a
./deploy.sh --init /deploy/app-a
./deploy.sh                    # 部署项目A

cd workspace/project-b  
./deploy.sh --init /deploy/app-b
./deploy.sh                    # 部署项目B

cd workspace/project-c
./deploy.sh --init /deploy/app-c
./deploy.sh                    # 部署项目C
```

**优点：**

- ✅ 每个项目独立配置，互不干扰
- ✅ 可以部署到不同的目录
- ✅ `.fuyou` 在项目根目录，便于管理
- ✅ 便于 CI/CD 集成

## 🔍 故障排除

### 1. "未配置部署目录"错误

**错误信息：**

```
❌ 错误: 未配置部署目录
```

**解决方法：**

- 运行 `deploy.sh --init /path/to/deploy`
- 或设置 `DEPLOY_DIR` 环境变量

### 2. "部署目录不存在"错误

**错误信息：**

```
❌ 错误: 部署目录不存在: /path/to/deploy
💡 提示: 请先创建该目录，或重新配置部署路径
```

**解决方法：**

```bash
# 创建部署目录
mkdir -p /path/to/deploy

# 重新初始化
./spring-boot-shell-manager/deploy.sh --init /path/to/deploy
```

### 3. Maven 构建失败

**错误信息：**

```
❌ Maven 构建失败，已停止后续步骤。
```

**解决方法：**

- 检查 `pom.xml` 配置
- 确保 Maven 环境正确
- 检查网络连接（依赖下载）
- 查看详细错误信息并修复

### 4. rsync 命令不存在

**错误信息：**

```
bash: rsync: command not found
```

**解决方法：**

macOS:

```bash
# rsync 通常已预装，如未安装：
brew install rsync
```

Linux:

```bash
# Debian/Ubuntu
sudo apt-get install rsync

# RedHat/CentOS
sudo yum install rsync
```

## 📝 最佳实践

### 1. 配置文件管理

建议将 `.fuyou` 加入 `.gitignore`：

```bash
echo ".fuyou" >> .gitignore
```

每个开发者维护自己的本地配置。

### 2. 部署目录规划

```
~/deploy/
├── dev/          # 开发环境
│   ├── app.jar
│   ├── lib/
│   └── appconfig/
├── test/         # 测试环境
│   ├── app.jar
│   ├── lib/
│   └── appconfig/
└── prod-sim/     # 生产模拟环境
    ├── app.jar
    ├── lib/
    └── appconfig/
```

### 3. 自动化工作流

创建 Makefile：

```makefile
.PHONY: deploy deploy-dev deploy-test

deploy:
	./spring-boot-shell-manager/deploy.sh

deploy-dev:
	DEPLOY_DIR=~/deploy/dev ./spring-boot-shell-manager/deploy.sh

deploy-test:
	DEPLOY_DIR=~/deploy/test ./spring-boot-shell-manager/deploy.sh
```

使用：

```bash
make deploy-dev
```

### 4. 部署前检查

在脚本执行前确保：

- [ ] Maven 环境正常
- [ ] 部署目录有足够空间
- [ ] 部署目录有写入权限
- [ ] 代码已提交到版本控制（可选）

## 🔗 相关文档

- [README.md](README.md) - 项目总体说明
- [MANUAL.md](STARTUP-MANUAL.md) - 启动脚本详细手册
- [examples/](examples/) - 配置示例

## ❓ 常见问题

### Q: 是否支持 Gradle 项目？

A: 当前仅支持 Maven。如需支持 Gradle，需要修改脚本中的构建命令。

### Q: 部署时会停止运行中的应用吗？

A: 不会。`deploy.sh` 只负责构建和文件同步，不会影响运行中的应用。需要手动使用 `startup.sh restart` 重启应用。

### Q: 可以部署到远程服务器吗？

A: 当前版本仅支持本地部署。远程部署建议使用 `rsync` over SSH 或其他部署工具。

### Q: 如何查看部署历史？

A: 脚本本身不记录历史。建议结合 Git 标签和部署日志管理版本。

### Q: 部署失败后如何回滚？

A: 建议在部署前备份部署目录，或使用版本控制工具管理部署产物。
