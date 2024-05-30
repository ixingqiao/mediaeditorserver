#!/bin/bash
# Description: This script concatenates multiple MP4 files with specified transitions between them using GPU for hardware acceleration and scaling.
# Usage: ./xfade-transitions.sh [--srcdir directory] [--files /path/to/1.mp4 /path/to/2.mp4 ...] [--transitions fade wipeleft ...] [--output ./concat/file.mp4] [--interval 1] [--bgmusic /path/to/music.mp3]
# Note: If options are not provided, default values will be used.

# Global variables
output_dir="./merge"
default_transitions=("circlecrop" "circleopen" "circleclose" "dissolve" "fadeblack" "fadewhite" "fade" "horzopen" "horzclose" "pixelize")
default_interval=1
output_file="$output_dir/xfade-concat.mp4"
src_dir="."
bg_music=""

# Help message function
function display_help() {
    echo "Usage: $0 [--srcdir directory] [--files /path/to/1.mp4 /path/to/2.mp4 ...] [--transitions fade wipeleft ...] [--output ./concat/file.mp4] [--interval 1] [--bgmusic /path/to/music.mp3]"
    echo "Concatenates multiple MP4 files with transitions between them."
    echo "Options:"
    echo "  --srcdir directory               Specify the directory containing MP4 files (default: current directory)"
    echo "  --files /path/to/1.mp4 /path/to/2.mp4 ...          Specify the MP4 files to concatenate (default: all MP4 files in srcdir)"
    echo "  --transitions fade wipeleft ...  Specify the transitions to use (default: fade wipeleft wiperight wipeup wipedown)"
    echo "  --output ./concat/file.mp4       Specify the output file path and name (default: merge/ffmpeg-xfade-concat.mp4)"
    echo "  --interval 1                     Specify the duration of transitions in seconds (default: 1)"
    echo "  --bgmusic /path/to/music.mp3     Specify the background music file (default: no background music)"
}

# Logging function
function log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - INFO - xfade - $1"
}

# Error logging function
function log_error() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - ERROR - xfade - $1"
}

# Check if FFmpeg is installed
function check_ffmpeg() {
    if ! command -v ffmpeg &>/dev/null; then
        log_error "FFmpeg is not installed. Please install FFmpeg to proceed."
        exit 1
    fi
}

# Get video duration using ffprobe
function get_video_duration() {
    duration=$(ffprobe -v quiet -select_streams v:0 -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "$1")
    echo "scale=3; $duration/1" | bc -l
}

# Check if video parameters are consistent
function check_video_parameters() {
    log "check_video_parameters begin"
    local first_file="$1"
    shift
    for file in "$@"; do
        if ! ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate,width,height -of csv=p=0 "$first_file" | grep -q "$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate,width,height -of csv=p=0 "$file")"; then
            log_error "Video parameters are inconsistent. Aborting concatenation."
            exit 1
        fi
    done
    log "check_video_parameters end"
}

# Generate filter_complex string
function generate_filter_complex() {
    local vfstr=""
    local afstr=""
    for i in "${index_array[@]}"; do
        catlen=$(echo "${duration_array[$i]}-${interval}" | bc -l)
        vfstr+="[$i:v]split[v${i}00][v${i}10];"
        afstr+="[$i:a]asplit[a${i}00][a${i}10];"
    done

    for i in "${index_array[@]}"; do
        catlen=$(echo "${duration_array[$i]}-${interval}" | bc -l)
        vfstr+="[v${i}00]trim=0:$catlen[v${i}01];"
        vfstr+="[v${i}10]trim=$catlen:${duration_array[$i]}[v${i}11t];"
        vfstr+="[v${i}11t]setpts=PTS-STARTPTS[v${i}11];"
        afstr+="[a${i}00]atrim=0:$catlen[a${i}01];"
        afstr+="[a${i}10]atrim=$catlen:${duration_array[$i]}[a${i}11t];"
        afstr+="[a${i}11t]asetpts=PTS-STARTPTS[a${i}11];"
    done

    for ((i=0; i<$line; ++i)); do
        Index=$((i % length))
        log "Using transition: ${transitions[$Index]}"
        vfstr+="[v${i}11][v$((i+1))01]xfade=duration=${interval}:transition=${transitions[$Index]}[vt${i}];"
        afstr+="[a${i}11][a$((i+1))01]acrossfade=d=${interval}[at${i}];"
    done

    vfstr+="[v001]"
    afstr+="[a001]"
    for ((i=0; i<$line; ++i)); do
        vfstr+="[vt${i}]"
        afstr+="[at${i}]"
    done
    vfstr+="[v${line}11]concat=n=$((line+2))[outv];"
    afstr+="[a${line}11]concat=n=$((line+2)):v=0:a=1[outa];"

    concatenate_with_transitions_and_music "$vfstr" "$afstr"
}

# Concatenate videos with transitions and add background music
function concatenate_with_transitions_and_music() {
    local infile=""
    for file in "${filename_array[@]}"; do
        infile+=" -hwaccel nvdec -i \"$file\""
    done

    local music_input=""
    local music_filter=""
    if [[ -n $bg_music ]]; then
        music_input="-i \"$bg_music\""
        music_filter="[outa][${#index_array[@]}:a]amix=inputs=2:duration=first:dropout_transition=2[outa]"
    fi

    local cmd="ffmpeg -hide_banner${infile} ${music_input} \
    -filter_complex_script <(echo \"$1 $2 $music_filter\") \
    -map [outv] -map [outa] ${x264} ${ki} ${br} \
    -y \"$output_file\" 2>&1 "
    log "$cmd"
    bash -c "$cmd"
}

# Parse arguments
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
        --help)
            display_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            display_help
            exit 1
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

if [ ${#transitions[@]} -lt 1 ]; then
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
            exit 1
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

# 视频设置
x264=" -c:v h264_nvenc"
ki="-keyint_min 72 -g 72 -sc_threshold 0"
br="-b:v 3000k -minrate 3000k -maxrate 6000k -bufsize 6000k -b:a 128k -avoid_negative_ts make_zero -fflags +genpts"

# 检查视频参数是否一致
check_video_parameters "${filename_array[0]}" "${filename_array[@]:1}"

# transitions数组的长度
length=${#transitions[@]}

# 记录转换信息
log "Using ${length} transitions with ${interval}-second interval."

# 生成filter_complex字符串
generate_filter_complex

# 记录filter_complex生成完成
log "Filter complex generation completed."

log "xfade end."
