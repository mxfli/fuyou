#!/bin/bash
#
# 优雅停止配置文件
# 该文件用于自定义应用停止行为的参数
#

# 优雅停止等待时间（秒）- SIGTERM信号后等待应用自行关闭的时间
GRACEFUL_SHUTDOWN_TIMEOUT=30

# 强制终止等待时间（秒）- SIGINT信号后等待的时间
FORCE_KILL_TIMEOUT=10

# 是否启用Spring Boot Actuator shutdown端点
# 设置为 true 时，会首先尝试通过HTTP请求优雅关闭应用
ENABLE_ACTUATOR_SHUTDOWN=false

# Actuator管理端口（当启用Actuator shutdown时使用）
ACTUATOR_SHUTDOWN_PORT=8080

# Actuator shutdown请求超时时间（秒）
ACTUATOR_SHUTDOWN_TIMEOUT=5

# 示例：启用Actuator shutdown的配置
# ENABLE_ACTUATOR_SHUTDOWN=true
# ACTUATOR_SHUTDOWN_PORT=8081
# ACTUATOR_SHUTDOWN_TIMEOUT=10

echo "=> 已加载自定义优雅停止配置"