#!/bin/bash

# 监控的目录
MONITOR_DIR="/data"
# 指定的最大大小（MB）
MAX_SIZE=5000
# 删除几个小时之前的文件（小时）
INITIAL_HOURS_AGO=1

# 获取目录当前大小（字节）
current_size=$(du -sb "$MONITOR_DIR" | cut -f1)
echo "Current size of $MONITOR_DIR: $((current_size / 1024 / 1024)) MB"

# 将最大大小转换为字节
MAX_SIZE_BYTES=$((MAX_SIZE * 1024 * 1024))

# 定义一个函数来删除旧文件
delete_old_files() {
    local hours_ago=$1
    local current_time=$(date +%s)
    
    echo "Deleting files older than $hours_ago hours..."

    # 查找并删除指定小时之前的 .mp4 文件
    find "$MONITOR_DIR" -maxdepth 1 -type f -name "*.mp4" -printf "%T@ %p\n" | while read -r time file; do
        # 将时间戳转换为秒
        file_time=${time%.*}
        
        # 如果文件是指定小时之前的
        if [ $((current_time - file_time)) -gt $((hours_ago * 3600)) ]; then
            echo "Deleting old file: $file"
            rm "$file"
        fi
    done
}

# 初始化删除时间范围
hours_ago=$INITIAL_HOURS_AGO

# 如果目录大小超过了最大限制
while [ "$current_size" -gt "$MAX_SIZE_BYTES" ]; do
    delete_old_files $hours_ago

    # 再次检查大小
    current_size=$(du -sb "$MONITOR_DIR" | cut -f1)
    echo "Current size after cleanup: $((current_size / 1024 / 1024)) MB"

    # 增加删除时间范围
    hours_ago=$((hours_ago * 2))

    # 防止删除时间范围无限增长，如果超过一定范围就停止（例如，48小时）
    if [ $hours_ago -gt 48 ]; then
        echo "Deletion range exceeded 48 hours. Stopping cleanup."
        break
    fi
done

echo "Final size of $MONITOR_DIR: $((current_size / 1024 / 1024)) MB"