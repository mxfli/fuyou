#!/bin/bash
#
# setup.sh BDD 自动化测试脚本 (Linux Docker 版)
# 在隔离的 Docker 容器中运行测试
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SH="$PROJECT_DIR/setup.sh"

# 颜色输出
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
RESET='\033[0m'

print_green() {
    echo -e "${GREEN}$1${RESET}"
}

print_red() {
    echo -e "${RED}$1${RESET}"
}

print_yellow() {
    echo -e "${YELLOW}$1${RESET}"
}

# 检查 Docker 是否可用
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_red "错误: Docker 未安装"
        exit 1
    fi
    if ! docker info &> /dev/null; then
        print_red "错误: Docker 守护进程未运行"
        exit 1
    fi
    print_green "✓ Docker 环境检查通过"
}

# 创建测试 expect 脚本
create_test_script() {
    cat > "$PROJECT_DIR/test/setup_bdd_test.exp" << 'EOF'
#!/usr/bin/expect -f
set timeout 10

proc print_green {msg} {
    puts "\033\x5b32m$msg\033\x5b0m"
}
proc print_red {msg} {
    puts "\033\x5b31m$msg\033\x5b0m"
}
proc print_yellow {msg} {
    puts "\033\x5b33m$msg\033\x5b0m"
}

# 使用 zip 创建最小化的 JAR 文件 (不需要 JDK)
proc create_minimal_jar {filepath} {
    set tempdir [file dirname $filepath]
    set metainf "$tempdir/META-INF"
    file mkdir $metainf
    set fd [open "$metainf/MANIFEST.MF" w]
    puts $fd "Manifest-Version: 1.0"
    close $fd

    # 使用 zip 命令创建 JAR (ZIP 格式)
    set olddir [pwd]
    cd $tempdir
    catch {exec zip -q $filepath META-INF/MANIFEST.MF}
    cd $olddir

    file delete -force $metainf
}

# 场景1: 单 JAR
proc test_single_jar {} {
    print_yellow "\n=== BDD 场景 1: 单 JAR 文件自动选择 ==="
    set test_dir "/tmp/test/s1"
    set bin_dir "$test_dir/bin"
    file mkdir $bin_dir
    file copy "/app/setup.sh" "$bin_dir/setup.sh"
    create_minimal_jar "$test_dir/myapp-1.0.0.jar"

    spawn bash
    send "cd $bin_dir && bash setup.sh\r"

    expect {
        "自动选择唯一 JAR" { print_green "  ✓ 自动选择 JAR 成功" }
        timeout { print_red "  ✗ 超时"; exit 1 }
    }
    expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
    expect { "实例数量" { send "\r" } timeout { exit 1 } }
    expect { "Spring Profile" { send "test\r" } timeout { exit 1 } }
    expect { "初始堆内存" { send "1g\r" } timeout { exit 1 } }
    expect { "最大堆内存" { send "2g\r" } timeout { exit 1 } }
    expect { "所有配置已生成完成" { print_green "  ✓ 配置生成完成" } timeout { exit 1 } }
    expect eof
    print_green "  ✓ 场景 1 通过"
}

# 场景2: 多 JAR
proc test_multi_jar {} {
    print_yellow "\n=== BDD 场景 2: 多 JAR 文件手动选择 ==="
    set test_dir "/tmp/test/s2"
    set bin_dir "$test_dir/bin"
    file mkdir $bin_dir
    file copy "/app/setup.sh" "$bin_dir/setup.sh"
    create_minimal_jar "$test_dir/app-1.0.jar"
    create_minimal_jar "$test_dir/api-2.0.jar"

    spawn bash
    send "cd $bin_dir && bash setup.sh\r"

    expect { "找到多个 JAR" { print_green "  ✓ 显示 JAR 列表" } timeout { exit 1 } }
    expect { "请选择 JAR 编号" { send "2\r"; print_green "  ✓ 选择 JAR #2" } timeout { exit 1 } }
    expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
    expect { "实例数量" { send "\r" } timeout { exit 1 } }
    expect { "Spring Profile" { send "prod\r"; print_green "  ✓ Spring Profile: prod" } timeout { exit 1 } }
    expect { "初始堆内存" { send "512m\r" } timeout { exit 1 } }
    expect { "最大堆内存" { send "1g\r" } timeout { exit 1 } }
    expect { "所有配置已生成完成" { print_green "  ✓ 配置生成完成" } timeout { exit 1 } }
    expect eof
    print_green "  ✓ 场景 2 通过"
}

# 场景3: 多实例
proc test_multi_instance {} {
    print_yellow "\n=== BDD 场景 3: 多实例模式配置 ==="
    set test_dir "/tmp/test/s3"
    set bin_dir "$test_dir/bin"
    file mkdir $bin_dir
    file copy "/app/setup.sh" "$bin_dir/setup.sh"
    create_minimal_jar "$test_dir/app-1.0.jar"
    create_minimal_jar "$test_dir/api-2.0.jar"

    spawn bash
    send "cd $bin_dir && bash setup.sh\r"

    expect { "找到多个 JAR" {} timeout { exit 1 } }
    expect { "请选择 JAR 编号" { send "1\r" } timeout { exit 1 } }
    expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
    expect { "实例数量" { send "3\r"; print_green "  ✓ 实例数量: 3" } timeout { exit 1 } }
    expect { "起始端口" { send "8090\r"; print_green "  ✓ 起始端口: 8090" } timeout { exit 1 } }
    expect { "已创建 3 个实例配置" { print_green "  ✓ 3 个实例配置已创建" } timeout { exit 1 } }
    expect { "Spring Profile" { send "multi\r" } timeout { exit 1 } }
    expect { "初始堆内存" { send "\r" } timeout { exit 1 } }
    expect { "最大堆内存" { send "\r" } timeout { exit 1 } }
    expect { "所有配置已生成完成" { print_green "  ✓ 配置生成完成" } timeout { exit 1 } }
    expect eof
    print_green "  ✓ 场景 3 通过"
}

# 场景4: 无效输入
proc test_invalid {} {
    print_yellow "\n=== BDD 场景 4: 无效输入处理 ==="
    set test_dir "/tmp/test/s4"
    set bin_dir "$test_dir/bin"
    file mkdir $bin_dir
    file copy "/app/setup.sh" "$bin_dir/setup.sh"
    create_minimal_jar "$test_dir/app-1.0.jar"
    create_minimal_jar "$test_dir/api-2.0.jar"

    spawn bash
    send "cd $bin_dir && bash setup.sh\r"

    expect { "找到多个 JAR" {} timeout { exit 1 } }
    expect { "请选择 JAR 编号" { send "5\r"; print_green "  ✓ 输入无效编号: 5" } timeout { exit 1 } }
    expect {
        "输入无效，请输入有效编号" {
            print_green "  ✓ 系统提示输入无效"
            expect { "请选择 JAR 编号" { send "1\r" } }
        }
        "请选择 JAR 编号" { send "1\r"; print_green "  ✓ 重新输入: 1" }
        timeout { exit 1 }
    }
    expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
    expect { "实例数量" { send "\r" } timeout { exit 1 } }
    expect { "单实例模式" {} timeout { exit 1 } }
    expect { "Spring Profile" { send "default\r" } timeout { exit 1 } }
    expect { "初始堆内存" { send "\r" } timeout { exit 1 } }
    expect { "最大堆内存" { send "\r" } timeout { exit 1 } }
    expect { "所有配置已生成完成" { print_green "  ✓ 配置生成完成" } timeout { exit 1 } }
    expect eof
    print_green "  ✓ 场景 4 通过"
}

print_green "=========================================="
print_green "  setup.sh BDD 自动化测试套件 (Docker 版)"
print_green "=========================================="

file mkdir "/tmp/test"
test_single_jar
test_multi_jar
test_multi_instance
test_invalid

print_green ""
print_green "=========================================="
print_green "  所有 BDD 场景测试通过！"
print_green "=========================================="
exit 0
EOF
    chmod +x "$PROJECT_DIR/test/setup_bdd_test.exp"
    print_green "✓ 测试脚本已创建"
}

# 运行 Docker 测试
run_docker_test() {
    print_yellow "\n=== 启动 Docker 测试容器 ==="

    # 使用轻量级 alpine 镜像 (expect, bash, unzip, openjdk8-jre)
    docker run --rm \
        -v "$PROJECT_DIR/setup.sh:/app/setup.sh:ro" \
        -v "$PROJECT_DIR/test/setup_bdd_test.exp:/app/test.exp:ro" \
        --name setup_bdd_test \
        alpine:3.19 sh -c "
            apk add --no-cache expect bash unzip zip openjdk8-jre
            mkdir -p /tmp/test
            expect /app/test.exp
        "

    if [ $? -eq 0 ]; then
        print_green "\n✓ Docker 测试全部通过"
    else
        print_red "\n✗ Docker 测试失败"
        exit 1
    fi
}

# 清理
cleanup() {
    print_yellow "\n=== 清理 ==="
    docker rm -f setup_bdd_test 2>/dev/null || true
    rm -f "$PROJECT_DIR/test/setup_bdd_test.exp"
    print_green "✓ 清理完成"
}

# 主程序
main() {
    print_green "=========================================="
    print_green "  setup.sh BDD 自动化测试 (Docker 版)"
    print_green "=========================================="

    check_docker
    create_test_script
    run_docker_test
    cleanup

    print_green ""
    print_green "=========================================="
    print_green "  所有测试完成！"
    print_green "  Docker 容器已自动销毁"
    print_green "=========================================="
}

# 信号处理
trap cleanup EXIT

main "$@"
