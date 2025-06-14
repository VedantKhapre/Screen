# Screen Recording Script

A flexible screen recording cli for Wayland-based Linux systems with support for audio input selection and camera overlay.

## Features

- Record your screen with a single command
- Interactive selection of audio input devices (microphone, system audio)
- Optional camera overlay in the bottom-right corner
- Automatic handling of recording and post-processing
- Sensible default options with customization available

## Requirements

The script depends on the following tools:

- `wf-recorder` - For screen recording on Wayland
- `ffmpeg` - For video processing and camera capture
- `fzf` - For interactive selection menus
- `pulseaudio-utils` (includes `pactl`) - For audio device detection
- `v4l-utils` (includes `v4l2-ctl`) - For camera device detection

## Installation

1. Save the script to a location in your PATH (e.g., `~/bin/screen.sh`)
2. Make it executable:
   ```
   chmod +x ~/bin/screen.sh
   ```

## Usage

### Basic Usage

Run the script without arguments for an interactive experience:

```
./screen.sh
```

This will:
1. Prompt you to select an audio device
2. Ask if you want to use a camera
3. If yes, prompt you to select a camera device
4. Start recording your screen
5. Create a file named with the current timestamp (YYYYMMDDHHMM.mp4)

### Command Line Options

```
Usage: ./screen.sh [OPTIONS] [FILENAME]

OPTIONS:
    -h, --help          Show this help message
    -n, --no-audio      Record without audio
    -d, --device DEVICE Specify audio device directly
    --no-camera         Skip camera selection, record without camera
    --camera DEVICE     Specify camera device directly
    
FILENAME:
    Output filename (default: YYYYMMDDHHMM.mp4)
```

### Examples

```
# Interactive audio and camera selection
./screen.sh

# Record without audio, with camera selection
./screen.sh -n my_recording.mp4

# Record with audio selection, no camera
./screen.sh --no-camera recording.mp4

# Record without audio and camera
./screen.sh -n --no-camera recording.mp4
```

## How It Works

1. The script scans for available audio devices (inputs and outputs) using PulseAudio
2. It detects connected camera devices using v4l2
3. When recording with camera overlay:
   - Two separate recordings are made (screen and camera)
   - After stopping, ffmpeg combines them with the camera in the bottom-right corner
   - A gray border is added around the camera for visibility

## Stopping a Recording

Press `Ctrl+C` to stop the recording. The script will handle the cleanup and processing automatically.

## Troubleshooting

- **Camera not detected**: Ensure your webcam is connected and not in use by another application
- **Audio not working**: Try selecting a different audio device or check your system's audio configuration
- **Black screen**: This may happen on some Wayland compositors - check if wf-recorder works independently

## License

This script is provided as-is, feel free to modify and distribute as needed.