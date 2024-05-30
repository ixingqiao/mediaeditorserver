#!/bin/bash
# Description: This script concatenates multiple MP4 files with 1-second transitions between them using GPU for hardware acceleration and scaling.
# Usage: ./script_name.sh [--dir directory]
# Note: If --dir is not provided, the script assumes that all input MP4 files are in the current directory.

# Global variables
output_dir="merge"
output_file="$output_dir/ffmpeg-xfade-concat.mp4"
vf_file="_vfstr_.txt"
log_file="merge_log.txt"

# Default input directory
input_dir="."

# Help message function
function display_help() {
    echo "Usage: $0 [--dir directory] [--help]"
    echo "Concatenates multiple MP4 files with transitions between them."
    echo "Options:"
    echo "  --dir directory   Specify the directory containing MP4 files (default: current directory)"
    echo "  --help            Display this help message"
}

# Logging function
function log() {
    echo "[INFO] $(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$log_file"
}

# Error logging function
function log_error() {
    echo "[ERROR] $(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$log_file"
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
    duration=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=duration -of default=nokey=1:noprint_wrappers=1 "$1")
    echo "scale=3; $duration/1" | bc -l
}

# Check if video parameters are consistent
function check_video_parameters() {
    local first_file="$1"
    shift
    for file in "$@"; do
        if ! ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate,width,height -of csv=p=0 "$first_file" | grep -q "$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate,width,height -of csv=p=0 "$file")"; then
            log_error "Video parameters are inconsistent. Aborting concatenation."
            exit 1
        fi
    done
}

# Generate filter_complex string
function generate_filter_complex() {
    local vfstr=""
    for i in "${index_array[@]}"; do
        catlen=$(echo "${duration_array[$i]}-${interval}" | bc -l)
        vfstr+="[$i:v]split[v${i}00][v${i}10];"
    done

    for i in "${index_array[@]}"; do
        catlen=$(echo "${duration_array[$i]}-${interval}" | bc -l)
        vfstr+="[v${i}00]trim=0:$catlen[v${i}01];"
        vfstr+="[v${i}10]trim=$catlen:${duration_array[$i]}[v${i}11t];"
        vfstr+="[v${i}11t]setpts=PTS-STARTPTS[v${i}11];"
    done

    for ((i=0; i<$line; ++i)); do
        Index=$((i % length))
        log "Using transitions : ${transitions[$Index]}"
        vfstr+="[v${i}11][v$((i+1))01]xfade=duration=${interval}:transition=${transitions[$Index]}[vt${i}];"
    done

    vfstr+="[v001]"
    for ((i=0; i<$line; ++i)); do
        vfstr+="[vt${i}]"
    done
    vfstr+="[v${line}11]concat=n=$((line+2))[outv];"

    echo "$vfstr" > "$vf_file"
}

# Concatenate videos with transitions
function concatenate_with_transitions() {
    local infile=""
    for file in "${filename_array[@]}"; do
        infile+=" -hwaccel nvdec -i \"$file\""
    done

    if [ ! -d "$output_dir" ]; then
        mkdir "$output_dir" || {
            log_error "Failed to create output directory: $output_dir"
            exit 1
        }
    fi

    local cmd="ffmpeg -hide_banner${infile} \
    -filter_complex_script \"$vf_file\" \
    -map [outv] ${x264} ${ki} ${br} \
    -y \"$output_file\""
    log "$cmd"
    bash -c "$cmd"
}

# Main script
while [[ "$1" =~ ^- ]]; do
    case $1 in
        --dir)
            shift
            input_dir="$1"
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
    shift
done

# Check if FFmpeg is installed
check_ffmpeg

# Log script start
log "Script started."

# Initialize line counter
line=-1

# Navigate to input directory
cd "$input_dir" || {
    log_error "Failed to navigate to input directory: $input_dir"
    exit 1
}

# Count MP4 files in the directory
mp4_count=$(find . -maxdepth 1 -iname "*.mp4" | wc -l)
if [ "$mp4_count" -lt 2 ]; then
    log "There are fewer than 2 MP4 files in the directory. No concatenation needed."
    exit 0
fi

# Iterate through input MP4 files in the specified directory
for file in $(ls *.mp4 | sort); do
    # Increment line counter
    line=$((line+1))

    # Get duration of video file
    duration_array[$line]=$(get_video_duration "$file")

    # Store filename and index
    filename_array[$line]=$file
    index_array[$line]=$line
done

# Video settings
x264=" -c:v h264_nvenc"
ki="-keyint_min 72 -g 72 -sc_threshold 0"
br="-b:v 3000k -minrate 3000k -maxrate 6000k -bufsize 6000k -b:a 128k -avoid_negative_ts make_zero -fflags +genpts"

# Check if there are inconsistencies in video parameters
check_video_parameters "${filename_array[0]}" "${filename_array[@]:1}"

# Define transitions
transitions=( \
    "fade"        \
    "wipeleft"    \
    "wiperight"   \
    "wipeup"      \
    "wipedown"    \
    "slideleft"   \
    "slideright"  \
    "slideup"     \
    "slidedown"   \
    "circlecrop"  \
    "rectcrop"    \
    "distance"    \
    "fadeblack"   \
    "fadewhite"   \
    "radial"      \
    "smoothleft"  \
    "smoothright" \
    "smoothup"    \
    "smoothdown"  \
    "circleopen"  \
    "circleclose" \
    "vertopen"    \
    "vertclose"   \
    "horzopen"    \
    "horzclose"   \
    "dissolve"    \
    "pixelize"    \
    "diagtl"      \
    "diagtr"      \
    "diagbl"      \
    "diagbr"      \
)

# Length of transitions array
length=${#transitions[@]}

# Duration of transition
interval=1

# Log transition information
log "Using ${length} transitions with ${interval}-second interval."

# Generate filter_complex string
generate_filter_complex

# Log filter_complex generation completion
log "Filter complex generation completed."

# Concatenate videos with transitions
concatenate_with_transitions

