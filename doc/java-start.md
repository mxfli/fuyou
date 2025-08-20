# Java 应用启动脚本 (startup.sh) 使用手册

本文档详细介绍了 `startup.sh` 脚本的使用方法，该脚本用于管理生产环境中的 Java 应用，特别设计用于支持多实例部署。

## 1. 功能概述

- **多实例管理**: 通过 `servers.properties` 配置文件，支持在同一台服务器上部署和管理应用的多个独立实例。
- **生命周期控制**: 提供 `start`, `stop`, `restart`, `status` 等标准命令来控制应用实例的生命周期。
- **滚动重启**: 支持 `restart all` 命令，实现所有实例的逐个滚动重启，保障业务连续性。
- **状态检查**: 能够检查单个或所有实例的运行状态，包括进程ID和资源使用情况。
- **日志管理**: 自动创建日志目录，并将控制台输出和GC日志分别重定向到指定文件。
- **交互式操作**: 在不带参数运行时，提供菜单引导用户选择操作和实例，降低使用门槛。

## 2. 目录结构

脚本期望的应用目录结构如下：

```
/your/app/root/
├── src/
│   └── java/
│       ├── appconfig/              # (可选) 实例独立的配置文件目录
│       ├── lib/                    # (可选) 外部依赖库
│       ├── logs/                   # 全局日志目录
│       ├── your-app.jar            # Spring Boot 可执行 Jar 包
│       ├── servers.properties      # (可选) 多实例配置文件
│       └── start/
│           └── startup.sh          # 启动脚本
├── instance1/                  # (可选) 实例1的运行时目录
│   ├── appconfig/
│   └── logs/
└── instance2/                  # (可选) 实例2的运行时目录
    ├── appconfig/
    └── logs/
```

- **`src/java/`**: 应用的主目录。
- **`src/java/start/startup.sh`**: 启动脚本。
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

# default 实例在主目录 src/java/ 下运行
default=
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

## 5. 交互模式

如果直接运行 `./startup.sh` 而不带任何参数，脚本将进入交互模式：

1.  **选择操作**: 首先会列出 `start`, `stop`, `restart`, `status` 等可用操作，并要求用户选择。
2.  **选择实例**: 接着会列出 `servers.properties` 中配置的所有实例，并要求用户选择一个进行操作。

此模式适用于不熟悉命令行的用户。

## 6. 日志和PID文件

- **控制台日志**: 所有实例的标准输出和错误输出都会被重定向到 `src/java/logs/` 目录下的 `{APP_NAME}.out` 文件中。
- **应用日志**: 每个实例的应用日志（如 logback 生成的日志）会输出到各自的 `logs` 目录中。例如，`instance1/logs/`。
- **GC 日志**: GC相关的日志同样位于实例的 `logs` 目录。
- **PID 文件**: 每个实例成功启动后，会在其运行时目录下创建一个名为 `.app.pid` 的文件，其中包含了应用的进程ID。脚本通过此文件来判断应用是否在运行。