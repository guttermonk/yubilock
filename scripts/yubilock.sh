#!/usr/bin/env bash
#
# yubilock — respond to YubiKey removal.
#
# Behaviour is read from ~/.config/yubilock/config. The NixOS module writes
# that file for you; manual installs can create it by hand. With no config
# file present the defaults below reproduce the original behaviour: lock the
# session on removal, and nothing more.

STATE_FILE="$HOME/.cache/yubilock-state"
PID_FILE="$HOME/.cache/yubilock.pid"
LOG_FILE="$HOME/.cache/yubilock.log"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/yubilock/config"

# --- defaults -----------------------------------------------------------
# Empty string means "null" / do nothing for the action variables.
YUBILOCK_PRIMARY_ACTION="lock"    # "" | lock | poweroff | hibernate
YUBILOCK_GRACE_PERIOD=60          # seconds before the secondary action
YUBILOCK_SECONDARY_ACTION=""      # "" | lock | poweroff | hibernate
YUBILOCK_NOTIFY="false"
YUBILOCK_NOTIFY_TITLE="Yubilock"
YUBILOCK_NOTIFY_MESSAGE="YubiKey removed."

# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

log() {
    printf '[%s] %s\n' "$(date)" "$*" >> "$LOG_FILE"
}

# Nudge waybar so the indicator repaints immediately.
refresh_waybar() {
    pkill -SIGRTMIN+5 waybar 2>/dev/null
}

# Actions that never return. A secondary action behind one of these is
# unreachable, which the NixOS module rejects at build time.
is_terminal() {
    case "$1" in
        poweroff|hibernate) return 0 ;;
        *) return 1 ;;
    esac
}

# Is this machine actually able to hibernate and come back? A hibernate we
# cannot resume from is a data-loss button, so we check before relying on it.
hibernate_ok() {
    grep -qw disk /sys/power/state 2>/dev/null || return 1
    [ "$(cat /sys/power/resume 2>/dev/null)" != "0:0" ] || return 1
    awk 'NR > 1 && $3 + 0 > 0 { found = 1 } END { exit !found }' /proc/swaps
}

check_yubikey() {
    lsusb | grep -qi "yubikey"
}

notify() {
    [ "$YUBILOCK_NOTIFY" = "true" ] || return 0
    command -v notify-send > /dev/null 2>&1 || return 0
    notify-send "$YUBILOCK_NOTIFY_TITLE" "$YUBILOCK_NOTIFY_MESSAGE" 2>/dev/null
}

# Cut power as hard as this machine will allow.
#
# `systemctl poweroff -ff` bypasses the system manager entirely and calls
# reboot(RB_POWER_OFF) from systemctl itself — instant, but it needs
# CAP_SYS_BOOT, which a user service does not have. It only succeeds when the
# optional yubilock-poweroff helper is installed (see yubilock-system.nix).
#
# Otherwise fall back to logind. `-i` ignores inhibitor locks, so a browser
# with an open download cannot veto the shutdown, but the teardown is orderly
# and a hung unit can delay it by up to DefaultTimeoutStopSec.
poweroff_now() {
    if systemctl poweroff -ff 2>/dev/null; then
        return 0
    fi

    if systemctl start yubilock-poweroff.service 2>/dev/null; then
        log "Hard poweroff dispatched via yubilock-poweroff.service"
        return 0
    fi

    log "No privileged poweroff path; falling back to 'systemctl poweroff -i'"
    systemctl poweroff -i
}

do_action() {
    case "$1" in
        "")
            return 0
            ;;
        lock)
            log "Locking session"
            loginctl lock-session
            ;;
        poweroff)
            log "Powering off"
            poweroff_now
            ;;
        hibernate)
            if hibernate_ok; then
                log "Hibernating"
                systemctl hibernate -i
            else
                # Never silently downgrade to "do nothing" — that would leave
                # the disk decrypted while the user believes it is protected.
                log "Hibernate unavailable at action time; powering off instead"
                poweroff_now
            fi
            ;;
        *)
            log "Unknown action '$1' — ignoring"
            ;;
    esac
}

# Sleep up to $1 seconds, watching for anything that should abort the
# countdown. Returns 0 if the full period elapsed, 1 if cancelled.
wait_or_cancel() {
    local total="$1"
    local remaining="$1"
    local start
    start=$(date +%s)

    while [ "$remaining" -gt 0 ]; do
        if check_yubikey; then
            log "YubiKey reinserted — countdown cancelled"
            return 1
        fi

        if [ "$(cat "$STATE_FILE")" != "on" ]; then
            log "Yubilock switched off — countdown cancelled"
            return 1
        fi

        sleep 1
        remaining=$((remaining - 1))

        # If the wall clock ran far ahead of our sleeps, the machine was
        # suspended mid-countdown. Someone got past the LUKS passphrase to
        # resume it, so the countdown's premise no longer holds. Abandon it
        # rather than firing a terminal action against a stale timer — the
        # loop re-arms and times a fresh countdown on the next removal.
        if [ $(( $(date +%s) - start )) -gt $(( total + 5 )) ]; then
            log "Clock jumped (suspend/resume) — countdown abandoned"
            return 1
        fi
    done

    return 0
}

cleanup() {
    log "Cleanup triggered"
    rm -f "$PID_FILE"
    # Leave the state file alone so the setting survives a reboot.
    refresh_waybar
    exit 0
}

trap cleanup EXIT TERM INT

# --- startup ------------------------------------------------------------

log "Yubilock starting with PID $$"

if [ ! -f "$STATE_FILE" ]; then
    echo "off" > "$STATE_FILE"
    log "No state file found, defaulting to off"
else
    log "Using existing state: $(cat "$STATE_FILE")"
fi

echo $$ > "$PID_FILE"

log "Config: primary='${YUBILOCK_PRIMARY_ACTION:-none}' grace=${YUBILOCK_GRACE_PERIOD}s secondary='${YUBILOCK_SECONDARY_ACTION:-none}'"

# Warn once at startup rather than discovering it at the moment it matters.
if [ "$YUBILOCK_PRIMARY_ACTION" = "hibernate" ] || [ "$YUBILOCK_SECONDARY_ACTION" = "hibernate" ]; then
    if ! hibernate_ok; then
        log "WARNING: hibernate configured but this machine cannot resume from it (no resume device or no swap). Yubilock will power off instead."
        command -v notify-send > /dev/null 2>&1 && \
            notify-send -u critical "Yubilock: hibernate unavailable" \
                "This machine has no usable resume device. Yubilock will power off instead of hibernating." 2>/dev/null
    fi
fi

if [ -n "$YUBILOCK_SECONDARY_ACTION" ] && is_terminal "$YUBILOCK_PRIMARY_ACTION"; then
    log "WARNING: primary action '$YUBILOCK_PRIMARY_ACTION' ends the session, so secondary action '$YUBILOCK_SECONDARY_ACTION' can never run."
fi

refresh_waybar
log "YubiKey monitoring started"

# --- main loop ----------------------------------------------------------

while true; do
    if [ "$(cat "$STATE_FILE")" != "on" ]; then
        sleep 5
        continue
    fi

    if ! check_yubikey; then
        # Not armed until we have actually seen the key, so booting without
        # one plugged in cannot trigger anything.
        sleep 10
        continue
    fi

    log "YubiKey present — armed"

    while check_yubikey && [ "$(cat "$STATE_FILE")" = "on" ]; do
        sleep 1
    done

    if [ "$(cat "$STATE_FILE")" != "on" ]; then
        log "Yubilock switched off while armed"
        continue
    fi

    log "YubiKey removed"
    do_action "$YUBILOCK_PRIMARY_ACTION"
    notify

    if [ -n "$YUBILOCK_SECONDARY_ACTION" ] && ! is_terminal "$YUBILOCK_PRIMARY_ACTION"; then
        log "Grace period: ${YUBILOCK_GRACE_PERIOD}s until $YUBILOCK_SECONDARY_ACTION"
        if wait_or_cancel "$YUBILOCK_GRACE_PERIOD"; then
            do_action "$YUBILOCK_SECONDARY_ACTION"
        fi
    fi
done
