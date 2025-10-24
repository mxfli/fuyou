# Spring Boot 启动管理器使用手册

本手册详细介绍 `startup.sh` 和 `setup.sh` 脚本的使用方法。由于脚本提供了交互式引导功能，本手册主要作为参考文档。

## 📋 快速参考

### 基本命令

```bash
# 初始化
# 复制 setup.sh startup.sh 到项目根目录/bin 目录中
# cd /your-app/bin

# 配置向导（首次使用）
./setup.sh

# 启动应用
./startup.sh start

# 停止应用
./startup.sh stop

# 重启应用
./startup.sh restart

# 查看状态
./startup.sh status
```

### 多实例命令

```bash
# 操作所有实例
./startup.sh start all
./startup.sh stop all
./startup.sh restart all

# 操作指定实例
./startup.sh start instance-8080
./startup.sh stop instance-8081
```

## 🔧 配置向导 (setup.sh)

### 功能概述

`setup.sh` 提供交互式配置向导，自动生成所需的配置文件：

- **JAR文件检测**: 自动扫描并选择应用JAR文件
- **应用信息配置**: 解析应用名称、版本和主类
- **实例部署模式**: 选择单实例或多实例部署
- **端口分配**: 多实例时自动分配端口号
- **Spring Profile**: 智能检测和选择配置文件
- **JVM参数**: 交互式内存配置

### 生成的配置文件

- `set-env.sh` - 应用环境配置
- `jvm-env.sh` - JVM参数配置
- `shutdown-env.sh` - 优雅停止配置
- `servers.properties` - 多实例配置（多实例时）

## 🚀 启动脚本 (startup.sh)

### 核心特性

#### 智能JAR检测

- 自动识别 **Fat JAR** 和 **Thin JAR** 类型
- Fat JAR: `java -jar app.jar`
- Thin JAR: `java -cp "app.jar:lib/*" MainClass`

#### Spring Boot启动检查

基于日志关键字的智能启动状态检测：

- **成功标识**: `Started.*in.*seconds`
- **失败检测**: `Stopping`, `Shutdown`, `Application shutdown`
- **异常识别**: `Exception`, `Failed to start`, `startup failed`

#### 多实例管理

通过 `servers.properties` 配置多实例：

```properties
instance1=instance-8080
instance2=instance-8081
instance3=instance-8082
```

### 命令语法

```bash
./startup.sh [command] [instance_name | all]
```

**参数说明:**

- `command`: `start` | `stop` | `restart` | `status`
- `instance_name`: 实例名称（如：instance-8080）
- `all`: 操作所有实例

### 启动流程

1. **环境检查**: 加载配置文件和验证环境
2. **JAR检测**: 识别JAR类型和主类
3. **进程启动**: 使用合适的启动方式
4. **状态监控**: 等待Spring Boot启动完成（最多60秒）
5. **结果确认**: 基于日志确认启动状态

## 📁 目录结构

### 标准结构

```
your-app/
├── your-app.jar                    # Spring Boot应用
├── servers.properties              # 多实例配置
├── spring-boot-shell-manager/      # 管理器目录
│   ├── setup.sh                    # 配置向导
│   ├── startup.sh                  # 启动脚本
│   ├── set-env.sh                  # 环境配置
│   ├── jvm-env.sh                  # JVM参数
│   └── shutdown-env.sh             # 停止配置
└── instance-8080/                  # 实例目录
    ├── logs/                       # 日志目录
    │   ├── your-app.out            # 控制台日志
    │   └── application.log         # 应用日志
    └── appconfig/                  # 配置目录
        └── application-prod.yml    # Profile配置
```

### Thin JAR结构

```
your-app/
├── your-app.jar                    # Thin JAR
├── lib/                            # 依赖库目录
│   ├── spring-boot-*.jar
│   └── other-dependencies.jar
└── spring-boot-shell-manager/
```

## ⚙️ 配置文件详解

### set-env.sh - 应用环境

```bash
# 应用基本信息
APP_NAME="your-app"
APP_VERSION="1.0.0"
MAIN_CLASS="com.example.Application"
SPRING_PROFILES_ACTIVE="prod"
```

### jvm-env.sh - JVM参数

```bash
# 内存配置
JVM_XMS="2g"                        # 初始堆内存
JVM_XMX="4g"                        # 最大堆内存
JVM_METASPACE_SIZE="128m"           # Metaspace大小

# GC配置
JVM_MAX_GC_PAUSE_MS="200"           # GC最大暂停时间
JVM_IHOP="45"                       # G1GC启动阈值

# 其他配置
EXTRA_JAVA_OPTS=""                  # 额外JVM参数
```

### shutdown-env.sh - 停止配置

```bash
GRACEFUL_SHUTDOWN_TIMEOUT="30"      # 优雅停止等待时间
FORCE_KILL_TIMEOUT="10"             # 强制终止等待时间
ENABLE_ACTUATOR_SHUTDOWN="false"    # Actuator停止端点
```

## 🛡️ 安全机制

### 滚动重启保护

- **熔断机制**: 任一实例启动失败立即终止后续操作
- **业务连续性**: 保护正在运行的实例不受影响
- **超时控制**: 60秒启动超时，避免无限等待

### 环境隔离

- 配置变量仅在脚本作用域内有效
- 不使用 `export`，避免污染全局环境
- 多应用可安全共存

## 🔍 故障排除

### 常见问题

#### 1. JAR文件检测失败

```bash
# 检查JAR文件位置
ls -la ../*.jar

# 确保文件权限正确
chmod 644 ../your-app.jar
```

#### 2. 启动超时

```bash
# 查看控制台日志
tail -f instance-8080/logs/your-app.out

# 检查JVM内存配置
vi jvm-env.sh
```

#### 3. 端口冲突

```bash
# 检查端口占用
netstat -tlnp | grep 8080

# 修改端口配置
vi servers.properties
```

#### 4. Spring Profile问题

```bash
# 检查配置文件
ls -la instance-8080/appconfig/

# 验证Profile配置
grep -r "spring.profiles" instance-8080/appconfig/
```

### 日志查看

```bash
# 控制台日志（启动输出）
tail -f instance-8080/logs/your-app.out

# 应用日志
tail -f instance-8080/logs/application.log

# GC日志
tail -f instance-8080/logs/gc.log
```

## 📊 状态监控

### 状态检查

```bash
# 检查单个实例
./startup.sh status instance-8080

# 检查所有实例
./startup.sh status all
```

### 状态输出示例

```
=> 实例状态检查
实例名称: instance-8080
运行目录: /app/instance-8080
进程ID: 12345
进程状态: 运行中
启动时间: 2024-01-01 10:00:00
```

## 🎯 最佳实践

### 部署建议

1. **首次部署**: 使用 `setup.sh` 配置向导
2. **测试启动**: 先启动单个实例验证配置
3. **生产部署**: 配置多实例实现高可用
4. **监控配置**: 设置日志轮转和监控告警

### 运维建议

1. **定期检查**: 使用 `status all` 检查实例状态
2. **日志管理**: 定期清理或轮转日志文件
3. **配置备份**: 重要配置文件进行版本控制
4. **滚动更新**: 使用 `restart all` 进行无停机更新

### 性能优化

1. **内存调优**: 根据应用特点调整JVM参数
2. **GC优化**: 选择合适的垃圾收集器
3. **实例分布**: 多实例部署时考虑负载均衡
4. **资源监控**: 监控CPU、内存和网络使用情况

## 📝 注意事项

1. **权限要求**: 确保脚本有执行权限
2. **Java版本**: 确保Java环境正确配置
3. **端口规划**: 避免端口冲突
4. **资源限制**: 注意系统资源限制
5. **网络配置**: 确保防火墙和网络配置正确

---

💡 **提示**: 由于脚本提供了完整的交互式引导，大多数操作可以通过运行脚本并按提示操作完成。本手册主要用于深入了解脚本功能和故障排除。