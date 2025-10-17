# Java 应用启动脚本 (startup.sh) 使用手册

本文档详细介绍了 `startup.sh` 脚本的使用方法，该脚本专为生产环境中的Spring Boot应用设计，特别优化了多实例部署和启动状态检查机制。

## 1. 功能概述

### 🚀 核心特性

- **Spring Boot启动检查**: 基于日志关键字的智能启动状态检测，确保应用真正启动成功
- **多实例管理**: 通过 `servers.properties` 配置文件，支持在同一台服务器上部署和管理应用的多个独立实例
- **智能环境识别**: 自动识别单实例和多实例环境，提供相应的操作界面
- **滚动重启保护**: 带熔断机制的安全滚动重启，保障业务连续性
- **故障自动检测**: 检测启动过程中的异常和应用自动关闭情况
- **交互式操作**: 友好的菜单引导界面，降低使用门槛

### 🛡️ 安全机制

- **熔断保护**: 滚动重启时，任一实例启动失败立即终止后续操作
- **超时控制**: 60秒启动超时机制，避免无限等待
- **PID自动清理**: 检测到启动失败时自动清理无效的PID文件
- **业务连续性**: 保护正在运行的实例不受失败实例影响

### 📊 状态监控

- **实时检查**: 能够检查单个或所有实例的运行状态，包括进程ID和进程信息
- **启动状态**: 基于Spring Boot日志的准确启动状态判断
- **详细诊断**: 失败时提供完整的故障信息和恢复建议
- **日志管理**: 自动创建日志目录，并将控制台输出和GC日志分别重定向到指定文件

## 2. 目录结构

脚本期望的应用目录结构如下：

```
/your/app/root/
├── src/
│   └── java/
│       ├── appconfig/              # (可选) 应用/默认实例的配置目录；实例可在各自运行目录下提供 appconfig/
│       ├── lib/                    # (可选) 外部依赖库（由 loader.path 使用）
│       ├── logs/                   # 默认实例的日志目录；多实例时各实例使用其运行目录下的 logs/
│       ├── your-app.jar            # Spring Boot 可执行 Jar 包
│       ├── servers.properties      # (可选) 多实例配置文件
│       └── start/
│           ├── startup.sh          # 启动脚本
│           └── jvm-env.sh          # (可选) 外置 JVM 参数配置（全局）
├── instance1/                  # (可选) 实例1的运行时目录
│   ├── appconfig/              # (可选) 实例级配置
│   └── logs/                   # 实例级日志目录
└── instance2/                  # (可选) 实例2的运行时目录
    ├── appconfig/
    └── logs/
```

- **`src/java/`**: 应用的主目录。
- **`src/java/start/startup.sh`**: 启动脚本。
- **`src/java/start/jvm-env.sh`**: 外置 JVM 参数配置（可选，全局生效）。
- **`src/java/servers.properties`**: 多实例配置文件。如果不存在，脚本将作为单实例运行。
- **`instance1/`, `instance2/`**: 实例的运行时目录，在 `servers.properties` 中定义。

## 3. 多实例配置 (`servers.properties`)

通过在 `src/java/` 目录下创建 `servers.properties` 文件来启用多实例模式。文件格式为 `key=value`。

- `key`: 实例的唯一名称。
- `value`: 实例的运行时子目录（相对于 `src/java/`）。如果值为空，则实例在主目录 (`src/java/`) 下运行。

**示例 `servers.properties`:**

```properties
# 定义两个实例，api 和 worker
# api 实例在 src/java/api-server/ 目录下运行
api=api-server

# worker 实例在 src/java/worker-server/ 目录下运行
worker=worker-server
# server 实例在主目录 src/java/ 下运行
server=
```

## 4. 使用方法

### 命令行语法

```bash
cd /your/app/root/src/java/start/
./startup.sh [command] [instance_name | all]
```

- **`[command]`**: 必要参数。可选值为 `start`, `stop`, `restart`, `status`。
- **`[instance_name | all]`**: 可选参数。
    - `instance_name`: 指定要操作的实例名（在 `servers.properties` 中定义的 key）。
    - `all`: 对所有已配置的实例执行操作。
    - 如果省略，且配置了多实例，脚本会提示用户选择一个实例。

### 命令详解

- **启动应用**
  ```bash
  # 启动名为 api 的实例
  ./startup.sh start api

  # 启动所有实例
  ./startup.sh start all
  ```

- **停止应用**
  ```bash
  # 停止名为 api 的实例
  ./startup.sh stop api

  # 停止所有实例
  ./startup.sh stop all
  ```

- **重启应用**
  ```bash
  # 重启名为 api 的实例
  ./startup.sh restart api

  # 滚动重启所有实例（逐个进行，确保服务不中断）
  ./startup.sh restart all
  ```

- **查看状态**
  ```bash
  # 查看名为 api 的实例的状态
  ./startup.sh status api

  # 查看所有实例的状态
  ./startup.sh status all
  ```

## 5. Spring Boot启动检查机制

### 5.1 智能启动检查

脚本采用基于日志的启动状态检查，相比简单的进程检查更加准确：

- **成功标识**: 检查日志中的 `Started.*in.*seconds` 关键字
- **失败检测**: 监控应用关闭信号 (`Stopping`, `Shutdown`, `Application shutdown` 等)
- **异常识别**: 检测启动错误 (`Exception`, `Failed to start`, `startup failed` 等)

### 5.2 启动流程

```bash
./startup.sh start api
```

启动过程包括：
1. **基础检查**: 验证进程是否成功创建 (2秒)
2. **启动监控**: 等待Spring Boot启动完成 (最多60秒)
3. **状态确认**: 基于日志关键字确认启动状态
4. **自动清理**: 失败时自动清理PID文件

### 5.3 启动状态示例

**成功启动**:
```
=> 正在启动 nipis-gj-transfer-0.2.0-SNAPSHOT 实例 'api'...
=> 等待Spring Boot应用启动完成...
=> 等待中... (2/60秒)
=> 等待中... (4/60秒)
=> Spring Boot应用启动成功! (用时: 6秒)
=> nipis-gj-transfer-0.2.0-SNAPSHOT 实例 'api' 启动成功! (pid: 12345)
```

**启动失败**:
```
=> 正在启动 nipis-gj-transfer-0.2.0-SNAPSHOT 实例 'api'...
=> 等待Spring Boot应用启动完成...
=> 警告: 检测到应用关闭信号，启动失败
=> nipis-gj-transfer-0.2.0-SNAPSHOT 实例 'api' 启动失败
```

## 6. 滚动重启安全机制

### 6.1 熔断保护

滚动重启 (`restart all`) 具备熔断保护机制：

```bash
./startup.sh restart all
```

- **逐个重启**: 按配置顺序依次重启实例
- **失败即停**: 任一实例启动失败立即终止后续重启
- **业务保护**: 保持其他正在运行的实例不受影响

### 6.2 重启流程示例

**正常流程**:
```
=> 开始滚动重启所有实例（保障业务连续性）...
=> 发现 3 个实例
[1/3] 滚动重启实例: server1
  => 步骤1: 停止实例 server1
  => 步骤2: 等待 3 秒后启动实例 server1
  => Spring Boot应用启动成功!
✓ 实例 'server1' 滚动重启成功
  => 等待 10 秒确保服务稳定，然后重启下一个实例...
```

**失败保护**:
```
[2/3] 滚动重启实例: server2
  => 实例 server2 启动失败
✗ 实例 'server2' 滚动重启失败

⚠️  警告: 检测到重启失败，为保障业务连续性，立即终止滚动重启过程
=> 已成功重启: 1 个实例
=> 失败位置: 第 2 个实例 (server2)
=> 剩余未重启: 1 个实例

🛡️  保护措施: 保持其他正在运行的实例不受影响
📋 建议操作:
   1. 检查失败实例的日志文件
   2. 修复启动问题
   3. 手动重启失败的实例: ./startup.sh restart server2
   4. 确认修复后，可继续重启剩余实例
```

## 7. 交互模式

### 7.1 智能交互

如果直接运行 `./startup.sh` 而不带任何参数，脚本将进入交互模式：

**多实例环境**:
1. **选择操作**: 列出 `start`, `stop`, `restart`, `status` 等可用操作
2. **选择实例**: 列出所有配置的实例，支持多种选择方式：
   - 实例名称 (如: `api`)
   - 数字选择 (如: `1`)
   - `all` 或直接回车 - 操作所有实例

**单实例环境**:
```
未找到 servers.properties 配置文件
=> 单实例运行，直接开始执行第1步骤选择的操作
```

### 7.2 交互示例

```bash
$ ./startup.sh

请选择操作：
1. start   - 启动应用
2. stop    - 停止应用
3. restart - 重启应用
4. status  - 查看状态

请输入命令名称或对应数字 (start/stop/restart/status 或 1/2/3/4):
start

请选择要操作的实例 (直接按回车默认选择 all - 所有实例):

可用的实例:
1. server -> /path/to/app (默认)
2. server1 -> /path/to/app/server1  
3. server2 -> /path/to/app/server2

输入选项:
- 实例名称或对应数字
- 'all' 或直接按回车 - 操作所有实例

请输入选择:
[直接回车]

=> 即将执行命令: start (所有实例)
```

## 8. 故障排除

### 8.1 启动相关问题

**问题**: Spring Boot应用启动失败
- **现象**: 脚本显示"启动失败，请检查日志"
- **排查**: 
    1. 检查控制台日志: `tail -f <运行目录>/logs/<应用名>.out`
    2. 查找关键错误信息: `grep -E "(Exception|Error.*startup|Failed to start|Unable to start)" <运行目录>/logs/<应用名>.out`
- **常见原因**:
  - 端口冲突: 修改 `servers.properties` 中的端口配置
  - 配置错误: 检查 Spring Boot 配置文件
  - 依赖问题: 确认 JAR 包完整性

**问题**: 启动超时 (60秒后仍未完成)
- **现象**: 脚本显示"启动超时，请检查应用配置和日志"
- **排查**:
  1. 检查应用是否卡在某个初始化步骤
  2. 查看 CPU 和内存使用情况: `top -p {pid}`
- **解决**:
  - 增加 JVM 内存参数
  - 检查数据库连接配置
  - 优化应用启动配置

**问题**: 进程存在但应用未正常启动
- **现象**: 有 PID 文件但应用功能异常
- **排查**: 脚本的 Spring Boot 检查机制会自动检测此类问题
- **解决**: 脚本会自动清理无效的 PID 文件并报告启动失败

### 8.2 滚动重启问题

**问题**: 滚动重启中断
- **现象**: 显示"检测到重启失败，立即终止滚动重启过程"
- **处理步骤**:
  1. 查看失败实例的详细错误信息
  2. 修复启动问题
  3. 使用 `./startup.sh status all` 确认当前状态
  4. 手动重启失败的实例: `./startup.sh restart {failed_instance}`
  5. 继续重启剩余实例

**问题**: 重启过程中服务中断
- **预防**: 脚本的熔断机制会在检测到失败时立即停止
- **恢复**: 按照上述步骤逐个修复和重启

### 8.3 环境相关问题

**问题**: 单实例环境误识别为多实例
- **检查**: 确认 `servers.properties` 文件是否存在
- **解决**: 删除不需要的 `servers.properties` 文件

**问题**: 多实例环境误识别为单实例  
- **检查**: 确认 `servers.properties` 文件格式正确
- **解决**: 参考配置示例修复配置文件

### 8.4 权限和资源问题

**问题**: 权限不足
- **现象**: 无法创建日志文件或 PID 文件
- **解决**: 确保脚本执行用户有相应目录的读写权限

**问题**: 内存不足
- **检查**: `free -h` 查看系统内存
- **解决**: 调整 JVM 内存参数或增加系统内存

**问题**: 磁盘空间不足
- **检查**: `df -h` 查看磁盘使用情况  
- **解决**: 清理日志文件或扩展磁盘空间

### 8.5 调试模式

如需详细的执行过程信息，可以使用调试模式：

```bash
# 启用调试模式
bash -x ./startup.sh start api

# 查看详细的启动检查过程
./startup.sh start api 2>&1 | grep -E "(检查|启动|等待)"
```

## 9. 日志和文件位置

### 9.1 日志文件

- **控制台日志**: `<运行目录>/logs/<应用名>.out` - 标准输出和错误输出
- **应用日志**: `<运行目录>/logs/*.log` - Spring Boot 应用日志
- **GC 日志**: `<运行目录>/logs/gc.log` - JVM 垃圾回收日志

### 9.2 配置和状态文件

- **实例配置**: `servers.properties` - 多实例配置
- **PID 文件**: `<运行目录>/.app.pid` - 进程ID文件
- **启动脚本**: `startup.sh` - 主控制脚本

### 9.3 日志查看命令

```bash
# 实时查看控制台日志（每个实例）
tail -f <运行目录>/logs/<应用名>.out

# 查看启动成功标识
grep "Started.*in.*seconds" <运行目录>/logs/<应用名>.out

# 查看错误日志（启动失败常见关键字）
grep -E "(Exception|Error.*startup|Failed to start|Unable to start)" <运行目录>/logs/<应用名>.out

# 查看最近的控制台日志
tail -100 <运行目录>/logs/<应用名>.out
```

## 10. 最佳实践

### 10.1 生产环境建议

1. **监控设置**: 配置应用监控，监控启动状态和健康检查
2. **日志轮转**: 配置 logrotate 防止日志文件过大
3. **备份策略**: 定期备份配置文件和重要数据
4. **测试流程**: 在测试环境验证滚动重启流程

### 10.2 运维建议

1. **分批重启**: 大规模部署时考虑分批进行滚动重启
2. **健康检查**: 重启后验证应用功能正常性
3. **回滚准备**: 准备快速回滚方案
4. **文档维护**: 保持运维文档和配置同步更新

## 11. 外置 JVM 参数配置（jvm-env.sh）

为便于生产环境灵活调优，脚本支持通过外置 Shell 配置文件覆盖 JVM 可调参数。

- 配置文件位置：
    - 与 startup.sh 同目录：`src/java/start/jvm-env.sh`（全局生效）
- 支持 JDK 版本：JDK 8/11/17/21/25
    - **JDK 8**：自动使用 PermGen + 旧式 GC 日志（`-Xloggc`、`-XX:+PrintGCDetails`）
    - **JDK 11/17/21/25**：自动使用 Metaspace + 新式 GC 日志（`-Xlog:gc*`）
    - 脚本会自动检测 JDK 主版本并应用对应参数集，无需手动区分
- 变量清单（示例仅供参考，具体请查看模板文件）：
    - `JVM_XMS`、`JVM_XMX`：堆最小/最大（建议一致）
    - `JVM_METASPACE_SIZE`、`JVM_MAX_METASPACE_SIZE`：元空间初始/最大（JDK 11+ 使用）
    - `JVM_PERM_SIZE`、`JVM_MAX_PERM_SIZE`：永久代初始/最大（仅 JDK 8 使用）
    - `JVM_MAX_GC_PAUSE_MS`：期望最大 GC 暂停时间（毫秒）
    - `JVM_IHOP`：G1 初始标记触发阈值（百分比）
    - `JVM_GC_LOG_FILESIZE`、`JVM_GC_LOG_FILECOUNT`：GC 日志轮转
    - `JVM_THREAD_STACK_SIZE`：线程栈大小（可选）
    - `JVM_HEAP_DUMP_PATH`、`JVM_ERROR_FILE`：OOM/错误日志路径
    - `EXTRA_JAVA_OPTS`：追加自定义 JVM 参数

推荐做法：

- 小型服务：`JVM_XMS=2g`、`JVM_XMX=2g~4g`、`JVM_MAX_GC_PAUSE_MS=200`、`JVM_IHOP=45`
- 中型服务：`JVM_XMS=4g~8g`、`JVM_XMX=4g~8g`、`JVM_MAX_GC_PAUSE_MS=150~200`
- 大堆应用：可在 `EXTRA_JAVA_OPTS` 中开启 `-XX:+AlwaysPreTouch`（启动更慢但运行更稳）
- JDK 8 永久代：默认 `JVM_PERM_SIZE=256m`、`JVM_MAX_PERM_SIZE=512m`
- JDK 11+ 元空间：默认 `JVM_METASPACE_SIZE=128m`、`JVM_MAX_METASPACE_SIZE=512m`

说明：

- startup.sh 会自动检测 JDK 主版本并选择推荐参数集。
- JDK 8 使用 PermGen 与旧式 GC 日志；JDK 11+ 使用 Metaspace 与新式 `-Xlog` 日志。
- 若未提供 `jvm-env.sh`，脚本会使用内置的安全默认值。
