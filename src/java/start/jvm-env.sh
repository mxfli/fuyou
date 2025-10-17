#!/usr/bin/env bash
# jvm-env.sh — 可选的外置 JVM 参数配置（Shell 脚本格式）
#
# 作用：覆盖 startup.sh 内部的 JVM 可调参数，无需修改脚本即可按环境/实例调整。
# 放置位置：与 startup.sh 相同目录（${APP_HOME}/start/jvm-env.sh），全局生效。
#
# 适用 JDK：支持 JDK 8/11/17/21/25
# - JDK 8：使用 PermGen + 旧式 GC 日志（-Xloggc, -XX:+PrintGCDetails）
# - JDK 11/17/21/25：使用 Metaspace + 新式 GC 日志（-Xlog:gc*）
# 注意：脚本会自动检测 JDK 版本并应用对应参数，无需手动区分。
#
# 常见调整建议：
# - 服务型应用：Xms 与 Xmx 设为一致（避免运行时扩容带来的抖动）
# - 小型服务：2g/4g；中等：4g/4g~8g/8g；大型：16g+；请结合容器/机器内存与压测结果。
# - G1 调优：保守使用 MaxGCPauseMillis（100~300ms）与 IHOP（35~50），以稳定为先。
# - GC 日志：保留 5 个轮转文件，每个 20M；生产问题排查建议保留充分。
# - 元空间/PermGen：
#   * JDK 8：PermSize/MaxPermSize（默认 256m/512m）
#   * JDK 11+：MetaspaceSize/MaxMetaspaceSize（默认 128m/512m）
#
# 版本化推荐（默认值已在 startup.sh 内置，这里仅示例与注释）：
# - JDK 8：使用 G1，旧式 GC 日志；PermGen 默认 256m/512m
# - JDK 11/17/21/25：使用 G1，-Xlog:gc*,safepoint；可选开启 -XX:+AlwaysPreTouch（大堆但允许慢启动）
#
# 变量单位：m/M（MB）, g/G（GB）

# --- 堆大小（常改） ---
# 初始堆（通常与最大堆一致）
JVM_XMS=2g
# 最大堆
JVM_XMX=4g

# --- 元空间/PermGen（偶尔改） ---
# JDK 11+ 使用 Metaspace：
# 初始元空间大小（触发阈值），一般 64m~256m
JVM_METASPACE_SIZE=128m
# 最大元空间大小（不设表示不限制；若受限内存环境可设置）
JVM_MAX_METASPACE_SIZE=512m

# JDK 8 使用 PermGen（仅 JDK 8 生效）：
# 初始永久代大小
JVM_PERM_SIZE=256m
# 最大永久代大小
JVM_MAX_PERM_SIZE=512m

# --- GC 调优（按需改） ---
# 期望最大暂停时间（毫秒），100~300 之间按业务 SLO 调整
JVM_MAX_GC_PAUSE_MS=200
# G1 初始标记触发阈值（1~100，百分比），常用 35~50
JVM_IHOP=45

# --- GC 日志轮转 ---
# 单个 GC 日志文件大小（例如 20M）
JVM_GC_LOG_FILESIZE=20M
# 日志文件个数
JVM_GC_LOG_FILECOUNT=5

# --- 线程栈大小（可选） ---
# 一般保留默认；线程极多且内存吃紧时可适当下调，如 512k/1m
#JVM_THREAD_STACK_SIZE=1m

# --- OOM/错误日志 ---
# 堆转储文件路径（默认指向实例日志目录）
#JVM_HEAP_DUMP_PATH="${LOG_DIR}/heapdump.hprof"
# HotSpot 错误文件路径模板
#JVM_ERROR_FILE="${LOG_DIR}/hs_err_pid%p.log"

# --- 额外自定义 JVM 参数（追加） ---
# 可按需求添加，例如：
#  -XX:+AlwaysPreTouch
#  -XX:+DisableExplicitGC
EXTRA_JAVA_OPTS=""
