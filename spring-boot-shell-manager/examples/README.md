# Spring Boot Shell Manager - 配置示例

这个目录包含了 Spring Boot 应用启动管理器的各种配置示例和参考模板。

## 📁 目录结构

```
examples/
├── README.md                    # 本文件
├── .fuyou.example              # 部署配置示例
├── .gitignore.example          # Git 忽略文件示例
├── bin-config-example/         # 运行时配置示例
│   ├── jvm-env.sh             # JVM 参数配置
│   ├── set-env.sh             # 应用环境配置
│   └── shutdown-env.sh        # 优雅停止配置
└── springboot-http-app/        # Spring Boot 示例应用
    └── ...                     # Maven 项目源码
```

## 📋 配置文件说明

### 1. `.fuyou.example` - 部署配置示例

这是本地部署脚本使用的配置文件示例。

**使用方法：**

```bash
# 复制到项目根目录
cp examples/.fuyou.example .fuyou

# 编辑配置
vi .fuyou

# 或直接使用 deploy.sh --init 命令
./spring-boot-shell-manager/deploy.sh --init /path/to/deploy
```

**配置内容：**

```bash
# 部署目标目录（必须是绝对路径）
DEPLOY_DIR="/path/to/your/deploy/directory"
```

### 2. `.gitignore.example` - Git 忽略文件示例

建议将 `.fuyou` 等本地配置文件加入 Git 忽略列表。

**使用方法：**

```bash
# 将内容追加到项目的 .gitignore
cat examples/.gitignore.example >> .gitignore
```

### 3. `bin-config-example/` - 运行时配置示例

这些是由 `setup.sh` 生成的运行时配置文件的参考模板。

#### `jvm-env.sh` - JVM 参数配置

定义 JVM 内存、GC、线程等参数：

```bash
# JVM 内存配置
JVM_XMS="2g"                      # 初始堆内存
JVM_XMX="4g"                      # 最大堆内存
JVM_METASPACE_SIZE="128m"         # Metaspace初始大小
JVM_MAX_METASPACE_SIZE="512m"     # Metaspace最大大小

# GC 配置
JVM_MAX_GC_PAUSE_MS="200"         # GC最大暂停时间
JVM_IHOP="45"                     # G1GC启动阈值

# 其他配置
JVM_THREAD_STACK_SIZE="1m"        # 线程栈大小
EXTRA_JAVA_OPTS=""                # 额外JVM参数
```

#### `set-env.sh` - 应用环境配置

定义应用名称、版本、Profile 等：

```bash
# 应用基本信息
APP_NAME="your-app"
APP_VERSION="1.0.0"
MAIN_CLASS="com.example.Application"

# Spring 配置
SPRING_PROFILES_ACTIVE="prod"
```

#### `shutdown-env.sh` - 优雅停止配置

定义应用停止的行为：

```bash
# 优雅停止等待时间（秒）
GRACEFUL_SHUTDOWN_TIMEOUT="30"

# 强制终止等待时间（秒）
FORCE_KILL_TIMEOUT="10"

# 是否启用Actuator停止端点
ENABLE_ACTUATOR_SHUTDOWN="false"
```

### 4. `springboot-http-app/` - Spring Boot 示例应用

一个完整的 Spring Boot 示例项目，可用于测试部署脚本功能。

**使用方法：**

```bash
# 进入示例项目
cd examples/springboot-http-app

# 使用 deploy.sh 部署
../../deploy.sh --init ~/deploy/test
../../deploy.sh

# 进入部署目录配置运行环境
cd ~/deploy/test
./spring-boot-shell-manager/setup.sh

# 启动应用
./spring-boot-shell-manager/startup.sh start
```

## 🎯 使用场景

### 场景 1: 新项目快速集成

```bash
# 1. 将管理器复制到项目
cp -r spring-boot-shell-manager /path/to/your/project/

# 2. 配置部署路径
cd /path/to/your/project
./spring-boot-shell-manager/deploy.sh --init ~/deploy/myapp

# 3. 执行部署
./spring-boot-shell-manager/deploy.sh

# 4. 配置运行环境
cd ~/deploy/myapp
./spring-boot-shell-manager/setup.sh

# 5. 启动应用
./spring-boot-shell-manager/startup.sh start
```

### 场景 2: 多环境部署

```bash
# 开发环境
./spring-boot-shell-manager/deploy.sh --init ~/deploy/dev
DEPLOY_DIR=~/deploy/dev ./spring-boot-shell-manager/deploy.sh

# 测试环境
DEPLOY_DIR=~/deploy/test ./spring-boot-shell-manager/deploy.sh

# 生产模拟环境
DEPLOY_DIR=~/deploy/prod ./spring-boot-shell-manager/deploy.sh
```

### 场景 3: 自定义配置

```bash
# 1. 复制配置模板
cp examples/bin-config-example/*.sh ~/deploy/myapp/spring-boot-shell-manager/

# 2. 自定义编辑
vi ~/deploy/myapp/spring-boot-shell-manager/jvm-env.sh
vi ~/deploy/myapp/spring-boot-shell-manager/set-env.sh

# 3. 启动应用
cd ~/deploy/myapp
./spring-boot-shell-manager/startup.sh start
```

## 💡 最佳实践

### 1. 版本控制

```bash
# 将管理器脚本纳入版本控制
git add spring-boot-shell-manager/*.sh

# 本地配置文件不纳入版本控制
echo ".fuyou" >> .gitignore
echo "spring-boot-shell-manager/set-env.sh" >> .gitignore
echo "spring-boot-shell-manager/jvm-env.sh" >> .gitignore
```

### 2. 团队协作

每个团队成员维护自己的 `.fuyou` 配置：

```bash
# 开发者 A
./spring-boot-shell-manager/deploy.sh --init ~/workspace/deploy/myapp

# 开发者 B
./spring-boot-shell-manager/deploy.sh --init /data/deploy/myapp
```

### 3. CI/CD 集成

在 CI/CD 流水线中：

```bash
# 通过环境变量指定部署路径
export DEPLOY_DIR=/opt/apps/myapp
./spring-boot-shell-manager/deploy.sh
```

## 🔗 相关文档

- [../README.md](../README.md) - 主文档
- [../DEPLOY.md](../DEPLOY.md) - 部署脚本详细指南
- [../MANUAL.md](../MANUAL.md) - 启动脚本详细手册

## ❓ 常见问题

### Q: 如何在 IDE 中集成？

A: 参考 [DEPLOY.md](../DEPLOY.md) 中的 "IDE 集成" 章节。

### Q: 配置文件可以共享吗？

A: `.fuyou` 是本地配置，建议不共享。运行时配置文件（`set-env.sh` 等）可以根据需要共享或模板化。

### Q: 如何切换不同环境？

A: 使用环境变量覆盖：

```bash
DEPLOY_DIR=~/deploy/test ./spring-boot-shell-manager/deploy.sh
```

### Q: 示例应用如何使用？

A: 参考本文档中的 "场景 1: 新项目快速集成" 部分。
