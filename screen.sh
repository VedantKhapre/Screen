#!/bin/bash

# Audio device selection function similar to ani-cli's nth()
select_audio_device() {
    local prompt="$1"
    local devices=""
    
    # Get PulseAudio sources (microphones, line-in, etc.)
    echo "Scanning audio input devices..." >&2
    local sources=$(pactl list sources | grep -E "(Name:|Description:)" | sed 'N;s/\n/ /' | \
        sed -E 's/.*Name: ([^ ]+).*Description: (.+)/\1\t\2 (Input)/')
    
    # Get PulseAudio sinks (speakers, headphones - for system audio recording)
    echo "Scanning audio output devices..." >&2  
    local sinks=$(pactl list sinks | grep -E "(Name:|Description:)" | sed 'N;s/\n/ /' | \
        sed -E 's/.*Name: ([^ ]+).*Description: (.+)/\1\t\2 (Output)/')
    
    # Combine all devices
    devices=$(printf "%s\n%s" "$sources" "$sinks" | grep -v "^$")
    
    # Add option for no audio
    devices=$(printf "none\tNo audio recording\n%s" "$devices")
    
    # Check if any devices found
    if [ -z "$devices" ]; then
        echo "No audio devices found!" >&2
        return 1
    fi
    
    # Count devices
    local device_count=$(echo "$devices" | wc -l | tr -d "[:space:]")
    
    # If only one device (plus the "none" option), and it's not just "none"
    if [ "$device_count" -eq 2 ]; then
        local single_device=$(echo "$devices" | tail -n1)
        echo "Only one audio device found: $(echo "$single_device" | cut -f2)" >&2
        echo "$single_device" | cut -f1
        return 0
    fi
    
    # Use fzf for selection (similar to ani-cli's launcher function)
    local selected=$(echo "$devices" | fzf --reverse --cycle --prompt "$prompt" --delimiter='\t' --with-nth=2)
    
    if [ -z "$selected" ]; then
        echo "No audio device selected!" >&2
        return 1
    fi
    
    # Return the device name/ID
    echo "$selected" | cut -f1
}

# Camera selection function
select_camera_option() {
    local prompt="$1"
    local options=$(printf "no\tNo camera recording\nyes\tRecord camera (overlay in bottom-right)")

    # Use fzf for selection
    local selected=$(printf "%s" "$options" | fzf --reverse --cycle --prompt "$prompt" --delimiter='\t' --with-nth=2)

    if [ -z "$selected" ]; then
        echo "No camera option selected, defaulting to no camera" >&2
        echo "no"
        return 0
    fi

    # Return the camera choice
    echo "$selected" | cut -f1
}

# Detect available camera devices
detect_camera_devices() {
    local cameras=""
    
    echo "Scanning for camera devices..." >&2
    
    # Check for video devices in /dev/video*
    for device in /dev/video*; do
        if [ -c "$device" ]; then
            # Try to get device name/info
            local device_info=$(v4l2-ctl --device="$device" --info 2>/dev/null | grep "Card type" | cut -d: -f2 | sed 's/^[[:space:]]*//')
            if [ -n "$device_info" ]; then
                cameras=$(printf "%s\n%s\t%s" "$cameras" "$device" "$device_info")
            else
                cameras=$(printf "%s\n%s\tCamera Device" "$cameras" "$device")
            fi
        fi
    done
    
    # Remove empty first line
    cameras=$(echo "$cameras" | grep -v "^$")
    
    # If no cameras found, return empty
    if [ -z "$cameras" ]; then
        echo "No camera devices found!" >&2
        return 1
    fi
    
    echo "$cameras"
}

# Select specific camera device
select_camera_device() {
    local prompt="$1"
    local cameras=$(detect_camera_devices)
    
    if [ $? -ne 0 ] || [ -z "$cameras" ]; then
        echo "No cameras available, trying default devices..." >&2
        # Try common video devices
        for default_cam in /dev/video0 /dev/video1 /dev/video2; do
            if [ -c "$default_cam" ]; then
                echo "$default_cam"
                return 0
            fi
        done
        echo "No camera devices found at all!" >&2
        return 1
    fi
    
    # Count cameras
    local camera_count=$(echo "$cameras" | wc -l | tr -d "[:space:]")
    
    # If only one camera, return it
    if [ "$camera_count" -eq 1 ]; then
        local single_camera=$(echo "$cameras" | head -n1)
        echo "Using camera: $(echo "$single_camera" | cut -f2)" >&2
        echo "$single_camera" | cut -f1
        return 0
    fi
    
    # Use fzf for selection
    local selected=$(echo "$cameras" | fzf --reverse --cycle --prompt "$prompt" --delimiter='\t' --with-nth=2)
    
    if [ -z "$selected" ]; then
        echo "No camera selected, using default /dev/video0" >&2
        echo "/dev/video0"
        return 0
    fi
    
    # Return the device path
    echo "$selected" | cut -f1
}

# Function to build wf-recorder audio arguments
build_audio_args() {
    local audio_device="$1"
    
    if [ "$audio_device" = "none" ]; then
        echo ""  # No audio flags
        return 0
    fi
    
    # Check if device exists and is available
    if pactl list sources | grep -q "Name: $audio_device" || pactl list sinks | grep -q "Name: $audio_device"; then
        echo "--audio-device=$audio_device -a"
    else
        echo "Warning: Selected audio device '$audio_device' not found, using default audio" >&2
        echo "-a"
    fi
}

# Check dependencies
check_deps() {
    local missing_deps=""
    
    command -v wf-recorder >/dev/null 2>&1 || missing_deps="$missing_deps wf-recorder"
    command -v fzf >/dev/null 2>&1 || missing_deps="$missing_deps fzf"
    command -v pactl >/dev/null 2>&1 || missing_deps="$missing_deps pulseaudio-utils"
    command -v ffmpeg >/dev/null 2>&1 || missing_deps="$missing_deps ffmpeg"
    command -v v4l2-ctl >/dev/null 2>&1 || missing_deps="$missing_deps v4l-utils"
    
    if [ -n "$missing_deps" ]; then
        echo "Missing dependencies:$missing_deps" >&2
        echo "Please install them and try again." >&2
        exit 1
    fi
}

# Get screen resolution for camera positioning
get_screen_resolution() {
    # Get screen resolution using wlr-randr (for Wayland) or xrandr (for X11)
    if command -v wlr-randr >/dev/null 2>&1; then
        wlr-randr | grep -E "[0-9]+x[0-9]+" | head -1 | grep -oE "[0-9]+x[0-9]+"
    elif command -v xrandr >/dev/null 2>&1; then
        xrandr | grep primary | grep -oE "[0-9]+x[0-9]+"
    else
        echo "1920x1080"  # Default fallback
    fi
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [FILENAME]

OPTIONS:
    -h, --help          Show this help message
    -n, --no-audio      Record without audio
    -d, --device DEVICE Specify audio device directly
    --no-camera         Skip camera selection, record without camera
    --camera DEVICE     Specify camera device directly
    
FILENAME:
    Output filename (default: YYYYMMDDHHMM.mp4)
    
Examples:
    $0                           # Interactive audio and camera selection
    $0 -n my_recording.mp4       # Record without audio, with camera selection
    $0 --no-camera recording.mp4 # Record with audio selection, no camera
    $0 -n --no-camera recording.mp4 # Record without audio and camera

EOF
}

# Parse command line arguments
FILENAME=""
AUDIO_MODE="select"  # select, none, device
AUDIO_DEVICE=""
CAMERA_MODE="select"  # select, none, device
CAMERA_DEVICE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -n|--no-audio)
            AUDIO_MODE="none"
            ;;
        -d|--device)
            if [ -z "$2" ]; then
                echo "Error: --device requires an argument" >&2
                exit 1
            fi
            AUDIO_MODE="device"
            AUDIO_DEVICE="$2"
            shift
            ;;
        --no-camera)
            CAMERA_MODE="none"
            ;;
        --camera)
            if [ -z "$2" ]; then
                echo "Error: --camera requires an argument" >&2
                exit 1
            fi
            CAMERA_MODE="device"
            CAMERA_DEVICE="$2"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_usage >&2
            exit 1
            ;;
        *)
            FILENAME="$1"
            ;;
    esac
    shift
done

# Set default filename if not provided
[ -z "$FILENAME" ] && FILENAME=$(date "+%Y%m%d%H%M").mp4

# Check dependencies
check_deps

# Handle audio device selection
AUDIO_ARGS=""
case "$AUDIO_MODE" in
    select)
        echo "Please select an audio device:"
        SELECTED_DEVICE=$(select_audio_device "Select audio device: ")
        if [ $? -ne 0 ] || [ -z "$SELECTED_DEVICE" ]; then
            echo "Audio device selection failed, recording without audio" >&2
            AUDIO_ARGS=""
        else
            AUDIO_ARGS=$(build_audio_args "$SELECTED_DEVICE")
            if [ "$SELECTED_DEVICE" != "none" ]; then
                echo "Selected audio device: $SELECTED_DEVICE" >&2
            fi
        fi
        ;;
    none)
        AUDIO_ARGS=""
        echo "Recording without audio" >&2
        ;;
    device)
        AUDIO_ARGS=$(build_audio_args "$AUDIO_DEVICE")
        echo "Using specified audio device: $AUDIO_DEVICE" >&2
        ;;
esac

# Handle camera selection
CAMERA_RECORD=""
case "$CAMERA_MODE" in
    select)
        echo ""
        echo "Please choose camera recording option:"
        CAMERA_CHOICE=$(select_camera_option "Record camera: ")
        if [ "$CAMERA_CHOICE" = "yes" ]; then
            echo "Please select camera device:"
            SELECTED_CAMERA=$(select_camera_device "Select camera: ")
            CAMERA_RECORD="yes"
            CAMERA_DEVICE="$SELECTED_CAMERA"
            echo "Selected camera: $CAMERA_DEVICE" >&2
        else
            echo "Recording without camera" >&2
            CAMERA_RECORD="no"
        fi
        ;;
    none)
        echo "Recording without camera" >&2
        CAMERA_RECORD="no"
        ;;
    device)
        echo "Using specified camera device: $CAMERA_DEVICE" >&2
        CAMERA_RECORD="yes"
        ;;
esac

# Start recording
echo ""
echo "=== Starting Screen Recording ==="
echo "Output file: $FILENAME"

if [ "$CAMERA_RECORD" = "yes" ]; then
    echo "Camera: $CAMERA_DEVICE (bottom-right overlay with grey border)"
    
    # Get screen resolution for overlay positioning
    SCREEN_RES=$(get_screen_resolution)
    SCREEN_WIDTH=$(echo "$SCREEN_RES" | cut -d'x' -f1)
    SCREEN_HEIGHT=$(echo "$SCREEN_RES" | cut -d'x' -f2)
    
    # Calculate camera overlay size and position (1/4 of screen width, maintain aspect ratio)
    CAM_WIDTH=$((SCREEN_WIDTH / 4))
    CAM_HEIGHT=$((CAM_WIDTH * 3 / 4))  # 4:3 aspect ratio
    
    # Position in bottom-right with 20px margin
    CAM_X=$((SCREEN_WIDTH - CAM_WIDTH - 20))
    CAM_Y=$((SCREEN_HEIGHT - CAM_HEIGHT - 20))
    
    echo "Camera overlay: ${CAM_WIDTH}x${CAM_HEIGHT} at position (${CAM_X},${CAM_Y})"
    
    # Create temporary files for camera and screen recording
    TEMP_DIR=$(mktemp -d)
    SCREEN_FILE="$TEMP_DIR/screen.mp4"
    CAMERA_FILE="$TEMP_DIR/camera.mkv"  # Changed to MKV format which worked for you
    
    echo "Press Ctrl+C to stop recording"
    echo ""
    
    # Start camera recording in background
    echo "Starting camera recording..."
    
    # Test camera access first
    if ! v4l2-ctl --device="$CAMERA_DEVICE" --info >/dev/null 2>&1; then
        echo "✗ Error: Cannot access camera device $CAMERA_DEVICE"
        echo "  Check if camera is connected and not in use by another application"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # MODIFIED: Using the settings that worked in your test
    ffmpeg -f v4l2 -video_size 640x480 -framerate 15 -i "$CAMERA_DEVICE" \
        -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
        -t 14400 "$CAMERA_FILE" -y > /dev/null 2>&1 &
    CAMERA_PID=$!
    
    # Wait a moment for camera to initialize
    sleep 2
    
    # Check if camera recording started successfully
    if ! ps -p $CAMERA_PID > /dev/null 2>&1; then
        echo "✗ Error: Camera recording failed to start"
        echo "  This may indicate camera access issues or insufficient permissions"
        rm -rf "$TEMP_DIR"
        exit 1
    else
        echo "✓ Camera recording started successfully"
    fi
    
    # Start screen recording
    echo "Starting screen recording..."
    if [ -n "$AUDIO_ARGS" ]; then
        wf-recorder $AUDIO_ARGS -f "$SCREEN_FILE" &
    else
        wf-recorder -f "$SCREEN_FILE" &
    fi
    SCREEN_PID=$!
    
    # Wait a moment for screen recording to initialize
    sleep 1
    
    # Check if screen recording started successfully
    if ! ps -p $SCREEN_PID > /dev/null 2>&1; then
        echo "✗ Error: Screen recording failed to start"
        echo "  Check if wf-recorder has the necessary permissions"
        [ -n "$CAMERA_PID" ] && kill -TERM "$CAMERA_PID" 2>/dev/null
        rm -rf "$TEMP_DIR"
        exit 1
    else
        echo "✓ Screen recording started successfully"
    fi
    
    # Function to handle cleanup and merging
    cleanup_and_merge() {
        echo ""
        echo "Stopping recordings..."
        
        # Stop both recordings gracefully
        [ -n "$CAMERA_PID" ] && kill -TERM "$CAMERA_PID" 2>/dev/null
        [ -n "$SCREEN_PID" ] && kill -TERM "$SCREEN_PID" 2>/dev/null
        
        # Wait for processes to finish gracefully
        sleep 1
        
        # Force kill if still running
        [ -n "$CAMERA_PID" ] && kill -KILL "$CAMERA_PID" 2>/dev/null
        [ -n "$SCREEN_PID" ] && kill -KILL "$SCREEN_PID" 2>/dev/null
        
        # Wait a moment for files to be written
        sleep 2
        
        echo "Processing recordings..."
        
        # Check if both files exist and have content before merging
        if [ -f "$SCREEN_FILE" ] && [ -s "$SCREEN_FILE" ] && [ -f "$CAMERA_FILE" ] && [ -s "$CAMERA_FILE" ]; then
            echo "Merging camera overlay with screen recording..."
            echo "Camera overlay: ${CAM_WIDTH}x${CAM_HEIGHT} at position (${CAM_X},${CAM_Y})"
            
            # MODIFIED: Simplified ffmpeg command with more compatible settings
            if ffmpeg -i "$SCREEN_FILE" -i "$CAMERA_FILE" \
                -filter_complex "[1:v]scale=${CAM_WIDTH}:${CAM_HEIGHT}[cam];[0:v][cam]overlay=${CAM_X}:${CAM_Y}[out]" \
                -map "[out]" -map 0:a? -c:a copy -c:v libx264 -preset medium -crf 23 \
                "$FILENAME" -y > /dev/null 2>&1; then
                echo "✓ Camera overlay merge completed successfully"
            else
                echo "⚠ Camera overlay merge failed, saving screen recording only..."
                mv "$SCREEN_FILE" "$FILENAME"
            fi
        elif [ -f "$SCREEN_FILE" ] && [ -s "$SCREEN_FILE" ]; then
            echo "⚠ Camera recording failed or empty, saving screen recording only..."
            mv "$SCREEN_FILE" "$FILENAME"
        else
            echo "✗ Recording failed - no valid files found!"
            echo "Debug information:"
            echo "  Screen file: $([ -f "$SCREEN_FILE" ] && echo "exists ($(stat -c%s "$SCREEN_FILE" 2>/dev/null || stat -f%z "$SCREEN_FILE" 2>/dev/null || echo "unknown") bytes)" || echo "missing")"
            echo "  Camera file: $([ -f "$CAMERA_FILE" ] && echo "exists ($(stat -c%s "$CAMERA_FILE" 2>/dev/null || stat -f%z "$CAMERA_FILE" 2>/dev/null || echo "unknown") bytes)" || echo "missing")"
            echo "  Temp dir: $TEMP_DIR"
            
            # Cleanup temporary files before exiting
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        # Verify final output
        if [ -f "$FILENAME" ] && [ -s "$FILENAME" ]; then
            FILE_SIZE=$(stat -c%s "$FILENAME" 2>/dev/null || stat -f%z "$FILENAME" 2>/dev/null || echo "unknown")
            echo "✓ Recording saved successfully: $FILENAME ($FILE_SIZE bytes)"
        else
            echo "✗ Final recording file is missing or empty!"
            exit 1
        fi
        
        # Cleanup temporary files
        rm -rf "$TEMP_DIR"
        exit 0
    }
    
    # Set up signal handling for clean shutdown
    trap cleanup_and_merge INT TERM
    
    # Wait for user to stop recording
    wait
    
else
    echo "Press Ctrl+C to stop recording"
    echo ""
    
    # Record screen only
    if [ -n "$AUDIO_ARGS" ]; then
        wf-recorder $AUDIO_ARGS -f "$FILENAME"
    else
        wf-recorder -f "$FILENAME"
    fi
    
    # Check if recording was successful
    if [ -f "$FILENAME" ] && [ -s "$FILENAME" ]; then
        FILE_SIZE=$(stat -c%s "$FILENAME" 2>/dev/null || stat -f%z "$FILENAME" 2>/dev/null || echo "unknown")
        echo ""
        echo "✓ Recording saved successfully: $FILENAME ($FILE_SIZE bytes)"
    else
        echo ""
        echo "✗ Recording failed or file is empty"
        exit 1
    fi
fi
EOF

# Make the script executable
chmod +x scripts/Screen/screen_fixed.sh

echo "Created modified script at scripts/Screen/screen_fixed.sh"
echo "Run it with: ./scripts/Screen/screen_fixed.sh"
