# Spring Boot 双打包模式测试应用

这是一个用于测试 `startup.sh` 脚本的 Spring Boot 应用，支持两种打包模式。

## 🎯 打包模式

### Fat JAR 模式（默认）

包含所有依赖的可执行 JAR 文件。

```bash
# 构建 Fat JAR
mvn clean package
# 或显式指定
mvn clean package -P fat-jar
```

### Thin JAR 模式

标准 Java JAR + 外部依赖库目录。

```bash
# 构建 Thin JAR
mvn clean package -P thin-jar
```

## 🚀 快速测试

运行自动化测试脚本：

```bash
./test-packaging.sh
```

该脚本会：

- 自动构建两种模式的 JAR 包
- 验证构建结果
- 对比文件大小
- 提供使用说明

## 📁 构建输出

```
target/
├── springboot-http-app-fat.jar     # Fat JAR (约 20MB)
├── springboot-http-app-thin.jar    # Thin JAR (约 10KB)
├── lib/                            # Thin JAR 依赖库 (约 20MB)
└── bin/                            # 启动脚本和配置
    ├── startup.sh
    ├── jvm-env.sh.example
    ├── shutdown-env.sh
    ├── servers.properties
    ├── jvm-env-fat.sh              # Fat JAR 配置
    ├── jvm-env-thin.sh             # Thin JAR 配置
    └── test-packaging.sh
```

## 🔧 启动方式

### 直接启动

**Fat JAR:**

```bash
cd target
java -jar springboot-http-app-fat.jar
```

**Thin JAR:**

```bash
cd target
java -cp "springboot-http-app-thin.jar:lib/*" com.example.DemoApplication
```

### 使用启动脚本（推荐）

```bash
cd target

# 选择配置模式
cp ../jvm-env-fat.sh bin/jvm-env.sh    # Fat JAR 模式
# 或
cp ../jvm-env-thin.sh bin/jvm-env.sh   # Thin JAR 模式

# 启动应用
./bin/startup.sh start

# 停止应用
./bin/startup.sh stop

# 重启应用
./bin/startup.sh restart

# 查看状态
./bin/startup.sh status
```

## 🌐 访问应用

应用启动后访问：

- 主页: http://localhost:8801/
- 健康检查: http://localhost:8801/actuator/health
- 应用信息: http://localhost:8801/actuator/info

## ⚠️ 重要提示

1. **始终使用 `mvn clean package`** 而不是 `mvn package`，以避免之前构建的残留文件干扰
2. **Fat JAR 和 Thin JAR 不能同时存在**，每次构建会覆盖之前的结果
3. **Thin JAR 模式需要 `lib/` 目录**，部署时需要一起复制
4. **启动脚本会自动检测 JAR 类型**，但建议使用对应的配置文件

## 🔍 故障排除

如果遇到问题：

1. 确保使用 `mvn clean package` 进行干净构建
2. 检查 Java 版本（需要 Java 8+）
3. 确保端口 8801 未被占用
4. 查看应用日志文件：`target/logs/application.log`