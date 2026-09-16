#!/usr/bin/env bash
#
# Drives scripts/yubilock.sh against stubbed system tools: a fake lsusb whose
# answer we control, and a systemctl/loginctl that log what they were asked to
# do instead of doing it. Covers the removal path end to end without anything
# that can actually power off the machine.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$(mktemp -d)"
trap 'kill "${MON:-}" 2>/dev/null; rm -rf "$BASE"' EXIT

mkdir -p "$BASE/bin" "$BASE/home/.cache" "$BASE/home/.config/yubilock"
export HOME="$BASE/home"
export YK_FLAG="$BASE/yubikey_present"
export ACTION_LOG="$BASE/actions.log"
: > "$ACTION_LOG"

cat > "$BASE/bin/lsusb" <<'EOF'
#!/bin/sh
if [ -f "$YK_FLAG" ]; then
  echo "Bus 001 Device 005: ID 1050:0407 Yubico.com Yubikey 4 OTP+U2F+CCID"
else
  echo "Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub"
fi
EOF

# Mirrors the real privilege situation: -ff needs CAP_SYS_BOOT and fails for a
# user service, the optional helper unit is absent, so only logind succeeds.
cat > "$BASE/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$ACTION_LOG"
case "$*" in
  *"poweroff -ff"*)            exit 1 ;;
  *"start yubilock-poweroff"*) exit 1 ;;
esac
exit 0
EOF

cat > "$BASE/bin/loginctl" <<'EOF'
#!/bin/sh
echo "loginctl $*" >> "$ACTION_LOG"
EOF

cat > "$BASE/bin/notify-send" <<'EOF'
#!/bin/sh
echo "notify-send $*" >> "$ACTION_LOG"
EOF

printf '#!/bin/sh\nexit 0\n' > "$BASE/bin/pkill"
chmod +x "$BASE"/bin/*
export PATH="$BASE/bin:$PATH"

fails=0

write_config() {
  cat > "$HOME/.config/yubilock/config" <<EOF
YUBILOCK_PRIMARY_ACTION="$1"
YUBILOCK_GRACE_PERIOD=$2
YUBILOCK_SECONDARY_ACTION="$3"
YUBILOCK_NOTIFY="${4:-false}"
YUBILOCK_NOTIFY_TITLE="Coalmine Canary"
YUBILOCK_NOTIFY_MESSAGE="The canary will no longer sing"
EOF
}

start_monitor() {
  : > "$ACTION_LOG"
  rm -f "$HOME/.cache/yubilock.log"
  echo "on" > "$HOME/.cache/yubilock-state"
  touch "$YK_FLAG"
  bash "$REPO/scripts/yubilock.sh" > /dev/null 2>&1 &
  MON=$!
  sleep 2                       # let it notice the key and arm
}

stop_monitor() { kill "$MON" 2>/dev/null; wait "$MON" 2>/dev/null; MON=""; }

check() { # description, pattern, expected match y/n
  if grep -q "$2" "$ACTION_LOG"; then got=y; else got=n; fi
  if [ "$got" = "$3" ]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1  (expected match=$3, got=$got)"
    echo "        actions: $(tr '\n' '|' < "$ACTION_LOG")"
    fails=$((fails + 1))
  fi
}

echo "== lock, 3s grace, poweroff - key stays out =="
write_config lock 3 poweroff
start_monitor
rm -f "$YK_FLAG"; sleep 6
check "screen locked"                "loginctl lock-session"   y
check "tried hard poweroff first"    "poweroff -ff"            y
check "tried the helper unit"        "start yubilock-poweroff" y
check "fell back to logind poweroff" "poweroff -i"             y
stop_monitor

echo "== reinsert during grace - poweroff cancelled =="
write_config lock 6 poweroff
start_monitor
rm -f "$YK_FLAG"; sleep 2; touch "$YK_FLAG"; sleep 6
check "screen locked" "loginctl lock-session" y
check "no poweroff"   "poweroff"              n
stop_monitor

echo "== toggle off during grace - poweroff cancelled =="
write_config lock 6 poweroff
start_monitor
rm -f "$YK_FLAG"; sleep 2; echo "off" > "$HOME/.cache/yubilock-state"; sleep 6
check "screen locked" "loginctl lock-session" y
check "no poweroff"   "poweroff"              n
stop_monitor

echo "== canary: no primary action, notification on =="
write_config "" 3 poweroff true
start_monitor
rm -f "$YK_FLAG"; sleep 6
check "screen NOT locked" "lock-session"                   n
check "canary notified"   "The canary will no longer sing" y
check "powered off"       "poweroff -i"                    y
stop_monitor

echo "== no config file at all - original behaviour =="
rm -f "$HOME/.config/yubilock/config"
start_monitor
rm -f "$YK_FLAG"; sleep 4
check "screen locked" "loginctl lock-session" y
check "no poweroff"   "poweroff"              n
stop_monitor

echo "== immediate poweroff: primary=poweroff, secondary=null =="
write_config poweroff 0 ""
start_monitor
rm -f "$YK_FLAG"; sleep 3
check "powered off" "poweroff -i"  y
check "no lock"     "lock-session" n
stop_monitor

echo
[ "$fails" -eq 0 ] && echo "state-machine: all checks passed" || echo "state-machine: $fails FAILED"
exit "$fails"
