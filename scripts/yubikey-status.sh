#!/usr/bin/env bash

STATE_FILE="$HOME/.cache/yubilock-state"
PID_FILE="$HOME/.cache/yubilock.pid"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/yubilock/config"

YUBILOCK_PRIMARY_ACTION="lock"
YUBILOCK_GRACE_PERIOD=60
YUBILOCK_SECONDARY_ACTION=""

# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Create state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "off" > "$STATE_FILE"
fi

current_state=$(cat "$STATE_FILE")

if lsusb | grep -qi "yubikey"; then
    yubikey_status="(inserted)"
else
    yubikey_status="(not present)"
fi

# Describe what removal will actually do. This goes in the tooltip rather than
# the bar text on purpose: someone running the canary config does not want
# their status bar announcing "poweroff" to whoever is looking over their
# shoulder. Hovering is a deliberate act; the bar is always on display.
if [ -n "$YUBILOCK_SECONDARY_ACTION" ]; then
    mode_desc="${YUBILOCK_PRIMARY_ACTION:-nothing}, then ${YUBILOCK_SECONDARY_ACTION} after ${YUBILOCK_GRACE_PERIOD}s"
    armed_class="yubilock-armed"
else
    mode_desc="${YUBILOCK_PRIMARY_ACTION:-nothing}"
    armed_class="yubilock-on"
fi

if [ "$current_state" = "on" ]; then
    # Check if process is actually running
    if [ -f "$PID_FILE" ] && ps -p "$(cat "$PID_FILE")" > /dev/null 2>&1; then
        echo "{\"text\": \"Yubilock: ON $yubikey_status\", \"class\": \"$armed_class\", \"tooltip\": \"On removal: $mode_desc $yubikey_status\", \"alt\": \"active\"}"
    else
        # Process died, update state
        echo "off" > "$STATE_FILE"
        echo "{\"text\": \"Yubilock: OFF $yubikey_status\", \"class\": \"yubilock-off\", \"tooltip\": \"Yubilock not running $yubikey_status\", \"alt\": \"inactive\"}"
    fi
else
    echo "{\"text\": \"Yubilock: OFF $yubikey_status\", \"class\": \"yubilock-off\", \"tooltip\": \"Yubilock disabled $yubikey_status\", \"alt\": \"inactive\"}"
fi
