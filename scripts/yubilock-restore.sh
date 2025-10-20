#!/usr/bin/env bash

    STATE_FILE="$HOME/.cache/yubilock-state"
    LOG_FILE="$HOME/.cache/yubilock-restore.log"
    
    echo "[$(date)] Checking yubilock state on login" >> "$LOG_FILE"
    
    # Create state file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
        echo "off" > "$STATE_FILE"
        echo "[$(date)] No state file found, defaulting to off" >> "$LOG_FILE"
        exit 0
    fi
    
    # Read the saved state
    saved_state=$(cat "$STATE_FILE")
    echo "[$(date)] Saved state: $saved_state" >> "$LOG_FILE"
    
    # If it was enabled before, re-enable it
    if [ "$saved_state" = "on" ]; then
        if ! systemctl --user is-active yubilock.service > /dev/null 2>&1; then
            echo "[$(date)] Restoring yubilock service" >> "$LOG_FILE"
            systemctl --user start yubilock.service
            echo "[$(date)] Yubilock service restored" >> "$LOG_FILE"
        else
            echo "[$(date)] Yubilock service already running" >> "$LOG_FILE"
        fi
    fi
