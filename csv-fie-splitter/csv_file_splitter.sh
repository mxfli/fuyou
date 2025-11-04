#!/bin/bash

# CSV文件分割脚本
# 将多个大型CSV文件按100万行重新分割

set -e  # 遇到错误时退出

# 配置参数
LINES_PER_FILE=1000000  # 每个新文件的数据行数
TOTAL_LINES_PER_FILE=$((LINES_PER_FILE + 1))  # 包含标题行

# 检查参数
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "使用方法: $0 <BASE_NAME> [开始编号]"
    echo "示例1 (单文件): $0 20211_BASE_29294556"
    echo "示例2 (多文件): $0 20211_BASE_29294556 00"
    exit 1
fi

BASE_NAME="$1"
START_INDEX="$2"

# 根据参数数量确定处理模式
if [ -z "$START_INDEX" ]; then
    echo "单文件模式: 检测文件 ${BASE_NAME}.csv"
    SINGLE_FILE_MODE=true
    INPUT_FILE="${BASE_NAME}.csv"
else
    echo "多文件模式: 处理文件系列 ${BASE_NAME}_${START_INDEX}.csv 开始"
    SINGLE_FILE_MODE=false
fi

# 初始化变量
current_output_file=""
current_output_lines=0
output_file_index=0
header_line=""
temp_dir="/tmp/csv_split_$$"

# 创建临时目录
mkdir -p "$temp_dir"

# 清理函数
cleanup() {
    echo "清理临时文件..."
    rm -rf "$temp_dir"
}
trap cleanup EXIT

# 获取CSV标题行的函数
get_header() {
    local file="$1"
    if [ -z "$header_line" ]; then
        header_line=$(head -n 1 "$file")
        echo "获取到CSV标题行: ${header_line:0:50}..."
    fi
}

# 创建新输出文件的函数
create_new_output_file() {
    local index=$(printf "%02d" $output_file_index)
    current_output_file="${BASE_NAME}_N_${index}.csv"
    
    echo "创建新输出文件: $current_output_file"
    
    # 写入标题行
    echo "$header_line" > "$current_output_file"
    current_output_lines=1
    
    output_file_index=$((output_file_index + 1))
}

# 检查单文件是否需要分割
check_single_file() {
    local file="$1"
    
    echo "检查文件: $file"
    
    if [ ! -f "$file" ]; then
        echo "错误: 文件不存在 - $file"
        exit 1
    fi
    
    local total_lines=$(wc -l < "$file")
    local data_lines=$((total_lines - 1))  # 减去标题行
    
    echo "文件总行数: $total_lines (标题行: 1, 数据行: $data_lines)"
    
    if [ $data_lines -le $LINES_PER_FILE ]; then
        echo "=================================="
        echo "文件无需分割"
        echo "=================================="
        echo "源文件数据行数 ($data_lines) 不超过设定的分割阈值 ($LINES_PER_FILE)"
        echo "建议: 直接使用源文件 $file"
        echo "=================================="
        return 1  # 返回1表示不需要处理
    fi
    
    echo "文件需要分割: 数据行数 ($data_lines) 超过阈值 ($LINES_PER_FILE)"
    return 0  # 返回0表示需要处理
}

# 处理单个输入文件的函数
process_input_file() {
    local input_file="$1"
    local file_desc="$2"
    
    echo "处理文件: $input_file ($file_desc)"
    
    if [ ! -f "$input_file" ]; then
        echo "文件不存在: $input_file"
        return 1
    fi
    
    # 获取标题行（仅从第一个文件获取）
    get_header "$input_file"
    
    # 计算文件总行数
    local total_lines=$(wc -l < "$input_file")
    local data_lines=$((total_lines - 1))
    echo "文件 $input_file 共有 $total_lines 行 (数据行: $data_lines)"
    
    # 如果需要创建新的输出文件
    if [ -z "$current_output_file" ] || [ $current_output_lines -ge $TOTAL_LINES_PER_FILE ]; then
        create_new_output_file
    fi
    
    # 计算当前输出文件还需要多少行数据
    local lines_needed=$((TOTAL_LINES_PER_FILE - current_output_lines))
    
    # 使用tail跳过标题行，然后处理数据
    local temp_file="$temp_dir/temp_data.csv"
    tail -n +2 "$input_file" > "$temp_file"
    
    local remaining_lines=$(wc -l < "$temp_file")
    echo "准备处理 $remaining_lines 行数据"
    
    # 处理当前文件的数据
    while [ $remaining_lines -gt 0 ] && [ -s "$temp_file" ]; do
        if [ $current_output_lines -ge $TOTAL_LINES_PER_FILE ]; then
            echo "文件 $current_output_file 已写满 ($current_output_lines 行)"
            create_new_output_file
            lines_needed=$((TOTAL_LINES_PER_FILE - current_output_lines))
        fi
        
        # 计算这次要处理的行数
        local lines_to_process=$lines_needed
        if [ $remaining_lines -lt $lines_needed ]; then
            lines_to_process=$remaining_lines
        fi
        
        echo "向 $current_output_file 写入 $lines_to_process 行数据"
        
        # 提取指定行数并追加到输出文件
        head -n $lines_to_process "$temp_file" >> "$current_output_file"
        
        # 更新计数器
        current_output_lines=$((current_output_lines + lines_to_process))
        
        # 从临时文件中删除已处理的行
        if [ $lines_to_process -eq $remaining_lines ]; then
            > "$temp_file"  # 清空文件
            remaining_lines=0
        else
            tail -n +$((lines_to_process + 1)) "$temp_file" > "$temp_file.new"
            mv "$temp_file.new" "$temp_file"
            remaining_lines=$((remaining_lines - lines_to_process))
        fi
        
        lines_needed=$((TOTAL_LINES_PER_FILE - current_output_lines))
    done
    
    rm -f "$temp_file"
}

# 单文件模式处理
process_single_file() {
    echo "开始单文件模式处理..."
    
    # 首先检查文件是否需要分割
    if ! check_single_file "$INPUT_FILE"; then
        exit 0  # 文件不需要分割，正常退出
    fi
    
    # 文件需要分割，继续处理
    echo "开始分割处理..."
    process_input_file "$INPUT_FILE" "单文件"
}

# 多文件模式处理
process_multiple_files() {
    echo "开始多文件模式处理..."
    echo "起始编号: $START_INDEX"
    
    # 将开始编号转换为数字以便递增
    local file_counter
    if [[ "$START_INDEX" =~ ^0+([0-9]+)$ ]]; then
        file_counter=${BASH_REMATCH[1]}  # 去掉前导零
        if [ -z "$file_counter" ]; then
            file_counter=0
        fi
    else
        file_counter=$(echo "$START_INDEX" | sed 's/^0*//')
        if [ -z "$file_counter" ]; then
            file_counter=0
        fi
    fi
    
    local files_processed=0
    
    # 循环处理所有输入文件
    while true; do
        local input_file_index=$(printf "%02d" $file_counter)
        local input_file="${BASE_NAME}_${input_file_index}.csv"
        
        if [ ! -f "$input_file" ]; then
            echo "未找到文件: $input_file，处理结束"
            break
        fi
        
        process_input_file "$input_file" "文件序号 $input_file_index"
        file_counter=$((file_counter + 1))
        files_processed=$((files_processed + 1))
        
        echo "已完成处理文件: $input_file"
    done
    
    if [ $files_processed -eq 0 ]; then
        echo "错误: 未找到任何以 ${BASE_NAME}_${START_INDEX}.csv 开始的文件"
        exit 1
    fi
    
    echo "多文件模式共处理了 $files_processed 个文件"
}

# 主处理逻辑
main() {
    echo "=================================="
    echo "CSV文件分割处理工具"
    echo "分割阈值: $LINES_PER_FILE 行数据"
    echo "输出文件格式: 1行标题 + $LINES_PER_FILE 行数据"
    echo "=================================="
    
    local start_time=$(date +%s)
    
    if [ "$SINGLE_FILE_MODE" = true ]; then
        process_single_file
    else
        process_multiple_files
    fi
    
    # 显示最终统计
    echo "=================================="
    echo "处理完成统计"
    echo "=================================="
    
    if [ -n "$current_output_file" ]; then
        echo "最后一个输出文件: $current_output_file (包含 $current_output_lines 行)"
    fi
    
    if [ $output_file_index -gt 0 ]; then
        echo "共创建了 $output_file_index 个输出文件"
        
        # 显示输出文件列表
        echo ""
        echo "输出文件列表:"
        if ls ${BASE_NAME}_N_*.csv >/dev/null 2>&1; then
            ls -lh ${BASE_NAME}_N_*.csv | while read -r line; do
                echo "  $line"
            done
            
            # 计算总大小
            local total_size=$(ls -l ${BASE_NAME}_N_*.csv | awk '{sum += $5} END {print sum}')
            local total_size_mb=$((total_size / 1024 / 1024))
            echo ""
            echo "输出文件总大小: ${total_size_mb} MB"
        else
            echo "  未找到输出文件"
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo ""
    echo "总处理时间: ${duration} 秒"
    echo "=================================="
}

# 执行主函数
main