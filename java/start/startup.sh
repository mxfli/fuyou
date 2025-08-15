#!/bin/bash
#
# 生产环境应用启动脚本
# 使用方法: ./startup.sh [start|stop|restart|status]
#

# 获取应用根目录（脚本所在目录的上一级）
APP_HOME=$(cd "$(dirname "$0")"/.. && pwd)
#APP_NAME="nipis-gj-transfer-0.1.4"
APP_NAME="nipis-gj-transfer-0.2.0-SNAPSHOT"
APP_JAR="${APP_HOME}/${APP_NAME}.jar"
PID_FILE="${APP_HOME}/bin/${APP_NAME}.pid"
LOG_DIR="${APP_HOME}/logs"
LOG_FILE="${LOG_DIR}/${APP_NAME}.out"

# 创建日志目录（如果不存在）
mkdir -p $LOG_DIR

# JVM 参数配置
JAVA_OPTS="-server \
    -Xms2g -Xmx4g \
    -XX:PermSize=256m -XX:MaxPermSize=512m \
    -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:InitiatingHeapOccupancyPercent=45 \
    -XX:G1HeapRegionSize=16m -XX:+ParallelRefProcEnabled \
    -XX:+UseStringDeduplication \
    -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=\${LOGS_DIR}/heapdump.hprof \
    -XX:ErrorFile=\${LOG_DIR}/hs_err_pid%p.log \
    -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:${LOGS_DIR}/gc.log \
    -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=20m \
    -XX:+DisableExplicitGC \
    -Djson.defaultWriterFeatures=LargeObject"

# 应用配置选项
CONFIG_OPTS="-Dspring.config.location=file:${APP_HOME}/appconfig/application-prod.yml -Dlogging.config=${APP_HOME}/appconfig/logback-spring.xml"

# Spring Boot Loader 配置
LOADER_OPTS="-Dloader.path=${APP_HOME}/config/,${APP_HOME}/lib/"

# 检查应用是否运行
check_pid() {
  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE")
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
      echo $pid
      return 0
    fi
  fi
  echo ""
  return 1
}

# 启动应用
start() {
  pid=$(check_pid)
  if [ -n "$pid" ]; then
    echo "=> $APP_NAME 已在运行中! (pid: $pid)"
    return 0
  fi

  echo "=> 正在启动 $APP_NAME..."
  # 使用 nohup 启动并将日志重定向到日志文件，同时在后台运行
  nohup java $JAVA_OPTS $CONFIG_OPTS $LOADER_OPTS -jar $APP_JAR > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  
  # 检查启动状态
  sleep 2
  pid=$(check_pid)
  if [ -n "$pid" ]; then
    echo "=> $APP_NAME 启动成功! (pid: $pid)"
    echo "=> 日志输出到: $LOG_FILE"
  else
    echo "=> $APP_NAME 启动失败，请检查日志: $LOG_FILE"
    exit 1
  fi
}

# 停止应用
stop() {
  pid=$(check_pid)
  if [ -z "$pid" ]; then
    echo "=> $APP_NAME 未运行"
    return 0
  fi
  
  echo "=> 正在停止 $APP_NAME (pid: $pid)..."
  kill $pid
  
  # 等待进程终止
  for ((i=1; i<=30; i++)); do
    if ! kill -0 $pid 2>/dev/null; then
      rm -f "$PID_FILE"
      echo "=> $APP_NAME 已停止"
      return 0
    fi
    sleep 1
  done
  
  # 如果进程仍然存在，使用强制终止
  echo "=> $APP_NAME 未能正常停止，正在强制终止..."
  kill -9 $pid
  rm -f "$PID_FILE"
  echo "=> $APP_NAME 已被强制停止"
}

# 重启应用
restart() {
  stop
  sleep 2
  start
}

# 检查应用状态
status() {
  pid=$(check_pid)
  if [ -n "$pid" ]; then
    echo "=> $APP_NAME 正在运行 (pid: $pid)"
    echo "=> 进程信息:"
    ps -f -p $pid
    echo "=> 日志文件: $LOG_FILE"
  else
    echo "=> $APP_NAME 未运行"
  fi
}

# 显示菜单并获取用户输入
show_menu() {
  echo "请选择操作："
  echo "1. start   - 启动应用"
  echo "2. stop    - 停止应用"
  echo "3. restart - 重启应用"
  echo "4. status  - 查看状态"
  echo ""
  echo "请输入命令名称或对应数字 (start/stop/restart/status 或 1/2/3/4):"
}

# 验证用户输入
validate_input() {
  local input="$1"
  case "$input" in
    start|1)
      echo "start"
      return 0
      ;;
    stop|2)
      echo "stop"
      return 0
      ;;
    restart|3)
      echo "restart"
      return 0
      ;;
    status|4)
      echo "status"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 执行对应的操作
execute_command() {
  local cmd="$1"
  case "$cmd" in
    start)
      start
      ;;
    stop)
      stop
      ;;
    restart)
      restart
      ;;
    status)
      status
      ;;
  esac
}

# 主逻辑
if [ $# -eq 0 ]; then
  # 没有提供参数，显示交互式菜单
  while true; do
    show_menu
    read -r user_input
    
    if [ -z "$user_input" ]; then
      echo "输入不能为空，请重新选择。"
      echo ""
      continue
    fi
    
    validated_cmd=$(validate_input "$user_input")
    if [ $? -eq 0 ]; then
      echo "执行命令: $validated_cmd"
      echo ""
      execute_command "$validated_cmd"
      break
    else
      echo "选择错误，请重新选择。"
      echo ""
    fi
  done
else
  # 提供了参数，按原来的方式处理
  case "$1" in
    start)
      start
      ;;
    stop)
      stop
      ;;
    restart)
      restart
      ;;
    status)
      status
      ;;
    *)
      echo "用法: $0 {start|stop|restart|status}"
      exit 1
      ;;
  esac
fi

exit 0
