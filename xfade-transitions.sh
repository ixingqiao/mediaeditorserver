#!/bin/bash
# Description: This script concatenates multiple MP4 files with specified transitions between them using GPU for hardware acceleration and scaling.
# Usage: ./xfade-transitions.sh [--srcdir directory] [--files /path/to/1.mp4 /path/to/2.mp4 ...] [--transitions fade wipeleft ...] [--output ./concat/file.mp4] [--interval 1] [--bgmusic /path/to/bgmusic.mp3] [--loopbgmusic]
# Note: If options are not provided, default values will be used.

# 默认参数配置
output_dir="./merge"
default_transitions=("circlecrop" "circleopen" "circleclose" "dissolve" "fadeblack" "fadewhite" "fade" "horzopen" "horzclose")
default_interval=1
output_file="$output_dir/xfade-concat.mp4"
src_dir="."
bg_music=""
loop_bg_music=false
x264=" -c:v h264_nvenc -preset fast -bf 0"
ki="-keyint_min 30 -g 60 -sc_threshold 0"
br="-profile:v high -crf 20 -b:v 4000k -minrate 3000k -maxrate 6000k -bufsize 6000k -avoid_negative_ts make_zero -fflags +genpts"

function display_help() {
    echo "Usage: $0 [--srcdir directory] [--files /path/to/1.mp4 /path/to/2.mp4 ...] [--transitions fade wipeleft ...] [--output ./concat/file.mp4] [--interval 1] [--bgmusic /path/to/bgmusic.mp3] [--loopbgmusic]"
    echo "Concatenates multiple MP4 files with transitions between them."
    echo "Options:"
    echo "  --srcdir directory               Specify the directory containing MP4 files (default: current directory)"
    echo "  --files /path/to/1.mp4 /path/to/2.mp4 ...  Specify the MP4 files to concatenate (default: all MP4 files in srcdir)"
    echo "  --transitions fade wipeleft ...  Specify the transitions to use (default: fade wipeleft wiperight wipeup wipedown)"
    echo "  --output ./concat/file.mp4       Specify the output file path and name (default: merge/ffmpeg-xfade-concat.mp4)"
    echo "  --interval 1                     Specify the duration of transitions in seconds (default: 1)"
    echo "  --bgmusic /path/to/bgmusic.mp3   Specify the background music file path (default: none)"
    echo "  --loopbgmusic                    Loop the background music if its duration is shorter than the concatenated video (default: false)"
}

function log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - INFO - xfade - $1"
}

function log_error() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - ERROR - xfade - $1"
}

# 安全删除文件
function safe_remove() {
    for file in "$@"; do
        if [ -f "$file" ]; then
            log_error "Removing file: $file"
            rm -f "$file"
        else
            log_error "File not found: $file"
        fi
    done
}

# 安全退出避免僵尸进程
function safe_exit() {
    log "safe exit: $1"
    local pids=$(jobs -p)
    if [ -n "$pids" ]; then
        log "wait: $pids"
        for pid in $pids; do
            log "wait: $pid"
            wait $pid 2>/dev/null
            log "game over:$pid"
        done
        log "game over"
    fi
    exit $1
}

# 捕获并处理信号
trap "safe_exit 1" SIGINT SIGTERM

# 函数获取并记录内存状态
function log_memory_status() {
    local free_output=$(free -h)
    log_error "$free_output"
}

# 函数获取并记录 GPU 状态
function log_gpu_status() {
    # local nvidia_output=$(nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv)
    log_error "log_gpu_status"
}

function check_ffmpeg() {
    if ! command -v ffmpeg &>/dev/null; then
        log_error "FFmpeg is not installed. Please install FFmpeg to proceed."
        safe_exit 1
    fi
}

# 获取视频时长
function get_video_duration() {
    duration=$(ffprobe -v quiet -select_streams v:0 -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "$1")
    echo "scale=3; $duration/1" | bc -l
}

# 检测视频参数是否一致，若分辨率帧率不一致则不处理
function check_video_parameters() {
    log "check_video_parameters begin"
    local first_file="$1"
    shift
    for file in "$@"; do
        if ! ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate,width,height -of csv=p=0 "$first_file" | grep -q "$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate,width,height -of csv=p=0 "$file")"; then
            log_error "Video parameters are inconsistent. Aborting concatenation."
            safe_exit 2
        fi
    done
    log "check_video_parameters end"
}

function generate_filter_complex() {
    local vfstr=""
    for i in "${index_array[@]}"; do
        catlen=$(echo "scale=3;${duration_array[$i]}-${interval}" | bc -l)
        vfstr+="[$i:v]split[v${i}00][v${i}10];"
    done

    for i in "${index_array[@]}"; do
        catlen=$(echo "scale=3; ${duration_array[$i]}-${interval}" | bc -l)
        vfstr+="[v${i}00]trim=0:$catlen[v${i}01];"
        vfstr+="[v${i}10]trim=$catlen:${duration_array[$i]}[v${i}11t];"
        vfstr+="[v${i}11t]setpts=PTS-STARTPTS[v${i}11];"
    done

    for ((i=0; i<$line; ++i)); do
        Index=$((i % length))
        log "Using transition: ${transitions[$Index]}"
        vfstr+="[v${i}11][v$((i+1))01]xfade=duration=${interval}:transition=${transitions[$Index]}[vt${i}];"
    done

    vfstr+="[v001]"
    for ((i=0; i<$line; ++i)); do
        vfstr+="[vt${i}]"
    done
    vfstr+="[v${line}11]concat=n=$((line+2))[outv];"
    concatenate_with_transitions "$vfstr"
    if [[ -n "$bg_music" ]]; then
        add_background_music
    fi
}

function concatenate_with_transitions() {
    local infile=""
    for file in "${filename_array[@]}"; do
        infile+=" -hwaccel nvdec -i \"$file\""
    done

    local cmd="ffmpeg -hide_banner${infile} \
    -filter_complex_script <(echo \"$1\") \
    -map [outv] ${x264} ${ki} ${br} \
    -y \"$output_file\" 2>&1 "
    log "$cmd"
    bash -c "$cmd"
    if [ $? -ne 0 ]; then
        log_error "FFmpeg failed to process the video files."
        log_memory_status
        log_gpu_status
        safe_remove $output_file
        safe_exit 3
    fi
}

function add_background_music() {
    log "add bgm begin."
    local temp_output="${output_file}_temp.mp4"
    local loop_filter=""
    if [[ -n "$bg_music" && $loop_bg_music == true ]]; then
        loop_filter="-stream_loop -1"
    fi
    local total_duration=$(get_video_duration "$output_file")

    local cmd="ffmpeg -hide_banner -an -i \"$output_file\" $loop_filter -i \"$bg_music\" \
        -c:v copy -c:a aac -map 0:v -map 1:a -t ${total_duration} -fflags +genpts -y \"$temp_output\" 2>&1"
    log "add music $cmd"
    bash -c "$cmd"

    if [ $? -ne 0 ]; then
        log_error "Failed to add bgm."
        log_memory_status
        log_gpu_status
        safe_remove $output_file $temp_output
        safe_exit 4
    fi
    mv "$temp_output" "$output_file"
    log "add bgm successfully."
}

# 参数
files=()
transitions=()
output_specified=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --srcdir)
            shift
            src_dir="$1"
            shift
            ;;
        --files)
            shift
            while [[ "$1" != --* && "$1" != "" ]]; do
                files+=("$1")
                shift
            done
            ;;
        --transitions)
            shift
            while [[ "$1" != --* && "$1" != "" ]]; do
                transitions+=("$1")
                shift
            done
            ;;
        --output)
            shift
            output_file="$1"
            output_specified=true
            shift
            ;;
        --interval)
            shift
            interval="$1"
            shift
            ;;
        --bgmusic)
            shift
            bg_music="$1"
            shift
            ;;
        --loopbgmusic)
            loop_bg_music=true
            shift
            ;;
        --help)
            display_help
            safe_exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            display_help
            safe_exit 4
            ;;
    esac
done

# 根据参数设置files和src_dir
if [[ ${#files[@]} -eq 0 ]]; then
    if [[ -n $src_dir ]]; then
        files=($(ls "$src_dir"/*.mp4 | sort))
    else
        src_dir="."
        files=($(ls ./*.mp4 | sort))
    fi
fi

if [[ ${#transitions[@]} -lt 1 ]]; then
    transitions=("${default_transitions[@]}")
fi

if [ -z "$interval" ]; then
    interval="$default_interval"
fi

# 设置默认输出路径
if [[ -z $output_specified || $output_specified = false ]]; then
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            log_error "Failed to create output directory: $output_dir"
            safe_exit 5
        }
    fi
    output_file="$output_dir/xfade-concat.mp4"
fi

# 检查FFmpeg是否已安装
check_ffmpeg

log "xfade started."

# 初始化行数计数器
line=-1

# 获取输入MP4文件的持续时间
duration_array=()
filename_array=()
index_array=()

for file in "${files[@]}"; do
    line=$((line+1))
    duration_array[$line]=$(get_video_duration "$file")
    filename_array[$line]=$file
    index_array[$line]=$line
done
# 检查视频参数是否一致
check_video_parameters "${filename_array[0]}" "${filename_array[@]:1}"

# transitions数组的长度
length=${#transitions[@]}
# 确保 length 非零以避免除零错误
if [[ $length -eq 0 ]]; then
    log_error "No transitions specified. Aborting."
    safe_exit 6
fi

# 记录转换信息
log "Using ${length} transitions with ${interval}-second interval."

# 生成filter_complex字符串
generate_filter_complex

# 记录filter_complex生成完成
log "Filter complex generation completed."

log "xfade end."
safe_exit 0