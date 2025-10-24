#!/bin/bash
#
# JVM 环境配置文件 - 测试环境
# 此文件会被 startup.sh 自动加载
#
# 注意：这些变量仅在当前脚本作用域内有效，不会污染全局环境
#

# JVM 内存配置（测试环境使用较小内存）
JVM_XMS="512m"
JVM_XMX="1g"
JVM_METASPACE_SIZE="128m"
JVM_MAX_METASPACE_SIZE="256m"

# JDK 8 PermGen 参数（如果使用JDK 8）
JVM_PERM_SIZE="128m"
JVM_MAX_PERM_SIZE="256m"

# GC 配置
JVM_MAX_GC_PAUSE_MS="200"
JVM_IHOP="45"

# GC 日志配置
JVM_GC_LOG_FILESIZE="10M"
JVM_GC_LOG_FILECOUNT="3"

# 线程栈大小（可选）
JVM_THREAD_STACK_SIZE="1m"

# 应用主类（测试Spring Boot应用）
MAIN_CLASS="org.springframework.boot.loader.JarLauncher"

# 额外的JVM参数
EXTRA_JAVA_OPTS="-Dspring.profiles.active=prod -Dserver.port=8801"

# 测试环境特定配置
echo "=> 加载测试环境JVM配置"
echo "   - 内存配置: ${JVM_XMS} -> ${JVM_XMX}"
echo "   - 主类: ${MAIN_CLASS}"
echo "   - 额外参数: ${EXTRA_JAVA_OPTS}"