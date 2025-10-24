# Spring Boot 应用启动管理器

一个智能的 Spring Boot 应用部署和管理工具，支持 **Fat JAR** 和 **Thin JAR** 自动识别，支持**多实例部署**，提供**交互式配置向导**。

## ✨ 核心特性

- 🔍 **智能JAR检测**: 自动识别Fat JAR和Thin JAR类型，选择最优启动方式
- 🎯 **交互式配置**: 友好的配置向导，一步步引导完成部署配置
- 🚀 **多实例支持**: 支持最多3个实例，自动端口分配和管理
- 🛡️ **环境隔离**: 配置变量作用域限制，避免污染系统环境
- 📊 **Spring Profile智能选择**: 自动检测配置文件，智能推荐Profile
- 💾 **JVM参数优化**: 交互式JVM内存配置，适配不同环境需求

## 🚀 快速开始

### 1. 准备工作

将 Spring Boot JAR 文件放到应用根目录，然后进入管理器目录：

```bash
# 目录结构示例
your-app/
├── your-app-1.0.0.jar              # 您的应用JAR
└── bin/      # 管理器目录
    ├── setup.sh                    # 配置向导 ⭐
    └── startup.sh                  # 启动脚本 ⭐
```

### 2. 运行配置向导

```bash
# pwd your-app
.bin/setup.sh
```

**配置向导将引导您完成：**

#### 📦 JAR文件选择

- 自动检测应用根目录中的JAR文件
- 多个JAR时提供选择列表
- 自动解析应用名称和版本号

#### 🏷️ 应用信息确认

- 智能解析JAR文件名获取应用名和版本
- 支持手动修改应用名称和版本
- 自动检测主类（Main-Class）

#### 🌐 实例部署配置

- **单实例模式**: 适合开发和测试环境
- **多实例模式**: 支持2-3个实例，适合生产环境负载均衡

#### 🔌 端口配置（多实例）

- 自动分配连续端口号（如：8080, 8081, 8082）
- 支持自定义起始端口
- 自动检测端口冲突

#### 📁 Spring Profile配置

- 自动扫描 `appconfig/` 目录中的配置文件
- 智能识别可用的Profile（如：dev, test, prod）
- 提供Profile选择列表，支持默认Profile

#### 💾 JVM内存配置

- **交互式内存设置**: 根据环境选择合适的内存大小
- **智能默认值**: 单实例(2g-4g)，多实例(1g-2g)
- **参数说明**: 提供JVM参数的详细说明

### 3. 启动应用

配置完成后，使用启动脚本管理应用：

```bash
# 启动应用
./startup.sh start

# 停止应用  
./startup.sh stop

# 重启应用
./startup.sh restart

# 查看状态
./startup.sh status

# 查看日志
./startup.sh logs
```

### 4. 多实例管理

多实例部署时的管理命令：

```bash
# 操作所有实例
./startup.sh start all
./startup.sh stop all
./startup.sh restart all

# 操作单个实例
./startup.sh start instance-8080
./startup.sh stop instance-8081
./startup.sh status instance-8082

# 查看特定实例日志
./startup.sh logs instance-8080
```

## 📁 目录结构

配置完成后的目录结构：

```
your-app/
├── your-app-1.0.0.jar              # Spring Boot应用
├── servers.properties              # 多实例配置（多实例时生成）
├── spring-boot-shell-manager/      # 启动管理器
│   ├── setup.sh                    # 配置向导
│   ├── startup.sh                  # 启动脚本
│   ├── set-env.sh                  # 环境配置（自动生成）
│   ├── jvm-env.sh                  # JVM参数（自动生成）
│   └── shutdown-env.sh             # 优雅停止配置（自动生成）
├── instance-8080/                  # 实例1（多实例时）
│   ├── logs/                       # 日志目录
│   │   ├── your-app.out            # 控制台日志
│   │   └── application.log         # 应用日志
│   └── appconfig/                  # 配置目录
│       └── application-prod.yml    # Profile配置
└── instance-8081/                  # 实例2（多实例时）
    ├── logs/
    └── appconfig/
```

## ⚙️ 配置文件说明

### set-env.sh - 应用环境配置

```bash
# 注意：变量仅在脚本作用域内有效，不污染全局环境
APP_NAME="your-app"
APP_VERSION="1.0.0"
MAIN_CLASS="com.example.Application"
SPRING_PROFILES_ACTIVE="prod"
```

### jvm-env.sh - JVM参数配置

```bash
# JVM内存配置
JVM_XMS="2g"                        # 初始堆内存
JVM_XMX="4g"                        # 最大堆内存
JVM_METASPACE_SIZE="128m"           # Metaspace初始大小
JVM_MAX_METASPACE_SIZE="512m"       # Metaspace最大大小

# GC配置
JVM_MAX_GC_PAUSE_MS="200"           # GC最大暂停时间
JVM_IHOP="45"                       # G1GC启动阈值

# 其他配置
JVM_THREAD_STACK_SIZE="1m"          # 线程栈大小
EXTRA_JAVA_OPTS=""                  # 额外JVM参数
```

### shutdown-env.sh - 优雅停止配置

```bash
GRACEFUL_SHUTDOWN_TIMEOUT="30"      # 优雅停止等待时间（秒）
FORCE_KILL_TIMEOUT="10"             # 强制终止等待时间（秒）
ENABLE_ACTUATOR_SHUTDOWN="false"    # 是否启用Actuator停止端点
```

## 🔧 支持的JAR类型

### Fat JAR（胖JAR）

- **特点**: 包含所有依赖的完整JAR包
- **启动方式**: `java -jar app.jar`
- **适用场景**: 简单部署，单文件分发

### Thin JAR（瘦JAR）

- **特点**: 仅包含应用代码，依赖外置在lib目录
- **启动方式**: `java -cp "app.jar:lib/*" MainClass`
- **适用场景**: 依赖共享，减少传输大小

**脚本会自动检测JAR类型并选择合适的启动方式。**

## 🎯 实例目录命名规则

实例目录采用 `instance-端口号` 格式：

- `instance-8080` - 端口8080的实例
- `instance-8081` - 端口8081的实例
- `instance-8082` - 端口8082的实例

启动脚本自动从目录名提取端口号，设置 `-Dserver.port=端口号` 参数。

## 🛠️ 高级功能

### 补丁类路径

在应用根目录创建 `patch_classpath/` 目录，放置需要热修复的class文件：

```
your-app/
├── patch_classpath/
│   └── com/example/BugFixClass.class
└── your-app.jar
```

### 自定义配置

在实例的 `appconfig/` 目录中放置配置文件：

```
instance-8080/appconfig/
├── application.yml              # 通用配置
├── application-prod.yml         # 生产环境配置
└── logback-spring.xml          # 日志配置
```

### 环境变量隔离

所有配置文件使用普通变量而非 `export`，确保：

- ✅ 变量仅在脚本作用域内有效
- ✅ 不会污染系统全局环境
- ✅ 多应用可安全共存

## 🔍 故障排除

### 1. JAR文件检测失败

```bash
# 确保JAR文件在应用根目录
ls -la ../*.jar

# 检查文件权限
chmod 644 ../your-app.jar
```

### 2. 启动失败

```bash
# 查看控制台日志
tail -f instance-8080/logs/your-app.out

# 查看应用日志
tail -f instance-8080/logs/application.log

# 检查端口占用
netstat -tlnp | grep 8080
```

### 3. 内存不足

```bash
# 调整JVM内存参数
vi jvm-env.sh

# 修改内存配置
JVM_XMS="1g"
JVM_XMX="2g"
```

### 4. 配置文件问题

```bash
# 验证配置文件语法
java -jar ../your-app.jar --spring.config.location=instance-8080/appconfig/ --spring.profiles.active=prod --spring.config.check
```

## 📋 测试验证

运行环境污染测试：

```bash
./test_env_pollution.sh
```

该脚本验证配置变量不会污染系统环境。

## 📝 注意事项

1. **权限要求**: 确保脚本有执行权限
2. **端口冲突**: 多实例部署时注意端口分配
3. **内存规划**: 根据服务器资源合理配置JVM内存
4. **日志管理**: 定期清理或配置日志轮转
5. **配置备份**: 重要配置文件建议版本控制

## 🎯 最佳实践

1. **开发环境**: 使用单实例模式，较小内存配置
2. **测试环境**: 使用多实例模式，模拟生产环境
3. **生产环境**: 根据负载配置实例数量和内存大小
4. **监控**: 配置应用监控和日志收集
5. **备份**: 定期备份配置文件和应用数据