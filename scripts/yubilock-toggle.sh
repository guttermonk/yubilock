#!/usr/bin/env bash
#
# Toggle the yubilock monitor on and off from the Waybar indicator.
#
# Works for both install paths: when the systemd user unit exists the monitor
# is started and stopped through systemd, so the service manager's view always
# matches reality. Without the unit (manual install) it falls back to running
# the monitor as a background process.

STATE_FILE="$HOME/.cache/yubilock-state"
PID_FILE="$HOME/.cache/yubilock.pid"

# `systemctl cat` succeeds whenever the unit file exists, whether or not it is
# currently running — which is exactly the "is this a module install?" question.
have_unit() {
    systemctl --user cat yubilock.service > /dev/null 2>&1
}

start_monitor() {
    if have_unit; then
        systemctl --user start yubilock.service
        return
    fi

    # Manual install: prefer a packaged `yubilock` on PATH, otherwise the
    # monitor script sitting next to this one.
    if command -v yubilock > /dev/null 2>&1; then
        yubilock &
    else
        "$(dirname "$0")/yubilock.sh" &
    fi
}

stop_monitor() {
    if have_unit; then
        systemctl --user stop yubilock.service
        return
    fi

    [ -f "$PID_FILE" ] || return 0
    pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null 2>&1; then
        kill "$pid"
    fi
}

# Create state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "off" > "$STATE_FILE"
fi

current_state=$(cat "$STATE_FILE")

sleep 1
if [ "$current_state" = "on" ]; then
    notify-send "Yubilock is shutting down" -e
    echo "off" > "$STATE_FILE"
    stop_monitor
    echo '{"text": "Yubilock: OFF", "class": "yubilock-off", "tooltip": "Yubilock disabled"}'
else
    echo "on" > "$STATE_FILE"
    notify-send "Yubilock is now starting" -e
    start_monitor
    echo '{"text": "Yubilock: ON", "class": "yubilock-on", "tooltip": "Yubilock enabled"}'
fi
