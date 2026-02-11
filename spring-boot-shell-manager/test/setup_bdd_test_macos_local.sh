#!/bin/bash
#
# setup.sh BDD 自动化测试脚本 (macOS 本地版)
# 在隔离的临时目录中运行测试，测试完成后自动清理
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

# 检查 expect 是否可用
check_expect() {
    if ! command -v expect &> /dev/null; then
        print_red "错误: 未安装 expect"
        echo "请安装: brew install expect"
        exit 1
    fi
    print_green "✓ expect 已安装"
}

# 创建临时测试目录
setup_test_dir() {
    TEST_ROOT=$(mktemp -d /tmp/setup_bdd_test_XXXXXX)
    print_yellow "测试目录: $TEST_ROOT"
}

# 运行单个场景测试
run_scenario() {
    local name="$1"
    local dir="$2"
    local expect_script="$3"

    print_yellow "\n=== $name ==="

    if expect "$expect_script"; then
        print_green "  ✓ $name 通过"
        return 0
    else
        print_red "  ✗ $name 失败"
        return 1
    fi
}

# 主程序
main() {
    print_green "=========================================="
    print_green "  setup.sh BDD 自动化测试 (macOS 本地版)"
    print_green "=========================================="

    check_expect
    setup_test_dir

    # 确保测试结束后清理
    trap 'rm -rf "$TEST_ROOT"; print_yellow "\n=== 清理 ==="; print_green "✓ 测试目录已清理: $TEST_ROOT"' EXIT

    local failed=0

    # ===== 场景 1: 单 JAR =====
    local s1_dir="$TEST_ROOT/s1"
    mkdir -p "$s1_dir/bin"
    cp "$SETUP_SH" "$s1_dir/bin/setup.sh"
    mkdir -p "$s1_dir/META-INF"
    echo "Manifest-Version: 1.0" > "$s1_dir/META-INF/MANIFEST.MF"
    (cd "$s1_dir" && zip -q myapp-1.0.0.jar META-INF/MANIFEST.MF)
    rm -rf "$s1_dir/META-INF"

    cat > "$TEST_ROOT/s1.exp" << EXP_EOF
set timeout 10
proc print_green {msg} { puts "\033\x5b32m\$msg\033\x5b0m" }
proc print_red {msg} { puts "\033\x5b31m\$msg\033\x5b0m" }
spawn bash -c "cd $s1_dir/bin && bash setup.sh"
expect { "自动选择唯一 JAR" { print_green "  ✓ 自动选择 JAR 成功" } timeout { print_red "  ✗ 超时"; exit 1 } }
expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
expect { "实例数量" { send "\r" } timeout { exit 1 } }
expect { "Spring Profile" { send "test\r" } timeout { exit 1 } }
expect { "初始堆内存" { send "1g\r" } timeout { exit 1 } }
expect { "最大堆内存" { send "2g\r" } timeout { exit 1 } }
expect { "所有配置已生成完成" {} timeout { exit 1 } }
expect eof
EXP_EOF

    run_scenario "BDD 场景 1: 单 JAR 文件自动选择" "$s1_dir" "$TEST_ROOT/s1.exp" || failed=1

    # ===== 场景 2: 多 JAR =====
    local s2_dir="$TEST_ROOT/s2"
    mkdir -p "$s2_dir/bin"
    cp "$SETUP_SH" "$s2_dir/bin/setup.sh"
    for jar in app-1.0.jar api-2.0.jar; do
        mkdir -p "$s2_dir/META-INF"
        echo "Manifest-Version: 1.0" > "$s2_dir/META-INF/MANIFEST.MF"
        (cd "$s2_dir" && zip -q "$jar" META-INF/MANIFEST.MF)
        rm -rf "$s2_dir/META-INF"
    done

    cat > "$TEST_ROOT/s2.exp" << EXP_EOF
set timeout 10
proc print_green {msg} { puts "\033\x5b32m\$msg\033\x5b0m" }
proc print_red {msg} { puts "\033\x5b31m\$msg\033\x5b0m" }
spawn bash -c "cd $s2_dir/bin && bash setup.sh"
expect { "找到多个 JAR 文件" { print_green "  ✓ 显示 JAR 列表" } timeout { print_red "  ✗ 超时"; exit 1 } }
expect { "请选择 JAR 编号" { send "2\r"; print_green "  ✓ 选择 JAR #2" } timeout { exit 1 } }
expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
expect { "实例数量" { send "\r" } timeout { exit 1 } }
expect { "Spring Profile" { send "prod\r" } timeout { exit 1 } }
expect { "初始堆内存" { send "512m\r" } timeout { exit 1 } }
expect { "最大堆内存" { send "1g\r" } timeout { exit 1 } }
expect { "所有配置已生成完成" {} timeout { exit 1 } }
expect eof
EXP_EOF

    run_scenario "BDD 场景 2: 多 JAR 文件手动选择" "$s2_dir" "$TEST_ROOT/s2.exp" || failed=1

    # ===== 场景 3: 多实例 =====
    local s3_dir="$TEST_ROOT/s3"
    mkdir -p "$s3_dir/bin"
    cp "$SETUP_SH" "$s3_dir/bin/setup.sh"
    for jar in app-1.0.jar api-2.0.jar; do
        mkdir -p "$s3_dir/META-INF"
        echo "Manifest-Version: 1.0" > "$s3_dir/META-INF/MANIFEST.MF"
        (cd "$s3_dir" && zip -q "$jar" META-INF/MANIFEST.MF)
        rm -rf "$s3_dir/META-INF"
    done

    cat > "$TEST_ROOT/s3.exp" << EXP_EOF
set timeout 10
proc print_green {msg} { puts "\033\x5b32m\$msg\033\x5b0m" }
proc print_red {msg} { puts "\033\x5b31m\$msg\033\x5b0m" }
spawn bash -c "cd $s3_dir/bin && bash setup.sh"
expect { "请选择 JAR 编号" { send "1\r"; print_green "  ✓ 选择 JAR #1" } timeout { print_red "  ✗ 超时"; exit 1 } }
expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
expect { "实例数量" { send "3\r"; print_green "  ✓ 实例数量: 3" } timeout { exit 1 } }
expect { "起始端口" { send "8090\r"; print_green "  ✓ 起始端口: 8090" } timeout { exit 1 } }
expect { "已创建 3 个实例配置" { print_green "  ✓ 3 个实例配置已创建" } timeout { exit 1 } }
expect { "Spring Profile" { send "multi\r" } timeout { exit 1 } }
expect { "初始堆内存" { send "\r" } timeout { exit 1 } }
expect { "最大堆内存" { send "\r" } timeout { exit 1 } }
expect { "所有配置已生成完成" {} timeout { exit 1 } }
expect eof
EXP_EOF

    run_scenario "BDD 场景 3: 多实例模式配置" "$s3_dir" "$TEST_ROOT/s3.exp" || failed=1

    # ===== 场景 4: 无效输入 =====
    local s4_dir="$TEST_ROOT/s4"
    mkdir -p "$s4_dir/bin"
    cp "$SETUP_SH" "$s4_dir/bin/setup.sh"
    for jar in app-1.0.jar api-2.0.jar; do
        mkdir -p "$s4_dir/META-INF"
        echo "Manifest-Version: 1.0" > "$s4_dir/META-INF/MANIFEST.MF"
        (cd "$s4_dir" && zip -q "$jar" META-INF/MANIFEST.MF)
        rm -rf "$s4_dir/META-INF"
    done

    cat > "$TEST_ROOT/s4.exp" << EXP_EOF
set timeout 10
proc print_green {msg} { puts "\033\x5b32m\$msg\033\x5b0m" }
proc print_red {msg} { puts "\033\x5b31m\$msg\033\x5b0m" }
spawn bash -c "cd $s4_dir/bin && bash setup.sh"
expect { "请选择 JAR 编号" { send "5\r"; print_green "  ✓ 输入无效编号: 5" } timeout { print_red "  ✗ 超时"; exit 1 } }
expect {
    "输入无效，请输入有效编号" { print_green "  ✓ 系统提示输入无效"; expect { "请选择 JAR 编号" { send "1\r" } } }
    "请选择 JAR 编号" { send "1\r"; print_green "  ✓ 重新输入: 1" }
    timeout { exit 1 }
}
expect { "未检测到主类" { send "\r" } timeout { exit 1 } }
expect { "实例数量" { send "\r" } timeout { exit 1 } }
expect { "单实例模式" {} timeout { exit 1 } }
expect { "Spring Profile" { send "default\r" } timeout { exit 1 } }
expect { "初始堆内存" { send "\r" } timeout { exit 1 } }
expect { "最大堆内存" { send "\r" } timeout { exit 1 } }
expect { "所有配置已生成完成" {} timeout { exit 1 } }
expect eof
EXP_EOF

    run_scenario "BDD 场景 4: 无效输入处理" "$s4_dir" "$TEST_ROOT/s4.exp" || failed=1

    if [ $failed -eq 0 ]; then
        print_green ""
        print_green "=========================================="
        print_green "  所有 BDD 场景测试通过！"
        print_green "  测试目录已完全清理"
        print_green "=========================================="
    else
        exit 1
    fi
}

main "$@"
