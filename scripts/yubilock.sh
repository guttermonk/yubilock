#!/usr/bin/env bash

PID_FILE="$HOME/.cache/yubilock.pid"
STATE_FILE="$HOME/.cache/yubilock-state"
LOG_FILE="$HOME/.cache/yubilock.log"
### UPDATE THE LOCKSCREEN FUNCTION BELOW WITH YOUR PREFERRED SCREEN LOCKING COMMAND

# Log startup
echo "[$(date)] Yubilock starting with PID $$" >> "$LOG_FILE"

# Create state file if it doesn't exist, but preserve existing state
if [ ! -f "$STATE_FILE" ]; then
    echo "off" > "$STATE_FILE"
    echo "[$(date)] No state file found, defaulting to off" >> "$LOG_FILE"
else
    echo "[$(date)] Using existing state: $(cat "$STATE_FILE")" >> "$LOG_FILE"
fi

# Write PID to file
echo $$ > "$PID_FILE"
echo "[$(date)] PID file written, state: $(cat "$STATE_FILE")" >> "$LOG_FILE"

# Function to clean up on exit
cleanup() {
    echo "[$(date)] Cleanup triggered" >> "$LOG_FILE"
    rm -f "$PID_FILE"
    # Don't modify state file - preserve it across reboots
    pkill -SIGRTMIN+5 waybar 2>/dev/null
    exit 0
}

# Set up signal handlers
trap cleanup EXIT TERM INT

# Function to check if a YubiKey is currently plugged in
check_yubikey() {
    if lsusb | grep -i "yubikey" > /dev/null; then
        return 0 # device is present
    else
        return 1 # device is not present
    fi
}

### Function to lock the screen
### You can replace this with your preferred screen locking command
### Examples:
### gnome-screensaver-command -l  # For GNOME
### loginctl lock-session         # systemd-based systems
### xscreensaver-command -lock    # For xscreensaver
### i3lock                        # For i3
lock_screen() {
    lockscreen
    echo "Screen locked at $(date)"
}

# Main monitoring loop
echo "[$(date)] YubiKey monitoring started" >> "$LOG_FILE"
echo "YubiKey monitoring started at $(date)"

# Signal waybar to update
pkill -SIGRTMIN+5 waybar 2>/dev/null

while true; do
    # Check if monitoring is enabled
    if [ "$(cat "$STATE_FILE")" != "on" ]; then
        # Monitoring is paused, wait and check again
        echo "[$(date)] YubiKey monitoring paused (state: off)" >> "$LOG_FILE"
        sleep 5
        continue
    fi

    # Only monitor when state is "on"
    if check_yubikey; then
        echo "[$(date)] YubiKey detected" >> "$LOG_FILE"
        echo "YubiKey detected at $(date)"

        # Wait until the YubiKey is removed
        while check_yubikey && [ "$(cat "$STATE_FILE")" = "on" ]; do
            sleep 1
        done

        # If we exited because service was disabled, continue the loop
        if [ "$(cat "$STATE_FILE")" != "on" ]; then
            echo "[$(date)] YubiKey monitoring paused" >> "$LOG_FILE"
            continue
        fi

        echo "[$(date)] YubiKey removed - locking screen" >> "$LOG_FILE"
        echo "YubiKey removed at $(date)"
        lock_screen
    else
        echo "[$(date)] No YubiKey detected. Checking again..." >> "$LOG_FILE"
        echo "No YubiKey detected. Checking again in 10 seconds..."
        # Check less frequently to reduce system load
        sleep 10
    fi
done
