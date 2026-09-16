#!/usr/bin/env bash
#
# A suspend/resume in the middle of the grace period must abandon the
# countdown, not fire a terminal action against a timer from before the machine
# went down. Simulated with a date(1) stub we can shove forward.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_DATE="$(command -v date)"
BASE="$(mktemp -d)"
trap 'kill "${MON:-}" 2>/dev/null; rm -rf "$BASE"' EXIT

mkdir -p "$BASE/bin" "$BASE/home/.cache" "$BASE/home/.config/yubilock"
export HOME="$BASE/home"
export YK_FLAG="$BASE/yubikey_present"
export ACTION_LOG="$BASE/actions.log"
export DATE_OFFSET="$BASE/date_offset"
export REAL_DATE
echo 0 > "$DATE_OFFSET"
: > "$ACTION_LOG"

cat > "$BASE/bin/lsusb" <<'EOF'
#!/bin/sh
[ -f "$YK_FLAG" ] && echo "ID 1050:0407 Yubico.com Yubikey 4" || echo "ID 1d6b:0002 root hub"
EOF

# Clock we can jump forward to imitate time passing while suspended.
cat > "$BASE/bin/date" <<'EOF'
#!/bin/sh
OFF=$(cat "$DATE_OFFSET" 2>/dev/null || echo 0)
if [ "${1:-}" = "+%s" ]; then
  echo $(( $("$REAL_DATE" +%s) + OFF ))
else
  exec "$REAL_DATE" "$@"
fi
EOF

cat > "$BASE/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$ACTION_LOG"
case "$*" in *"poweroff -ff"*|*"start yubilock-poweroff"*) exit 1 ;; esac
exit 0
EOF

cat > "$BASE/bin/loginctl" <<'EOF'
#!/bin/sh
echo "loginctl $*" >> "$ACTION_LOG"
EOF

printf '#!/bin/sh\nexit 0\n' > "$BASE/bin/pkill"
chmod +x "$BASE"/bin/*
export PATH="$BASE/bin:$PATH"

cat > "$HOME/.config/yubilock/config" <<'EOF'
YUBILOCK_PRIMARY_ACTION="lock"
YUBILOCK_GRACE_PERIOD=30
YUBILOCK_SECONDARY_ACTION="poweroff"
YUBILOCK_NOTIFY="false"
EOF

echo "on" > "$HOME/.cache/yubilock-state"
touch "$YK_FLAG"
bash "$REPO/scripts/yubilock.sh" > /dev/null 2>&1 &
MON=$!
sleep 2

fails=0
echo "== 30s countdown, machine 'suspends' for an hour at t=3s =="
rm -f "$YK_FLAG"
sleep 3
echo 3600 > "$DATE_OFFSET"        # resume, one hour later
sleep 4

if grep -q "lock-session" "$ACTION_LOG"; then
  echo "  PASS  screen locked on removal"
else
  echo "  FAIL  screen never locked"; fails=$((fails + 1))
fi

if grep -q "poweroff" "$ACTION_LOG"; then
  echo "  FAIL  stale timer fired poweroff after resume"
  echo "        actions: $(tr '\n' '|' < "$ACTION_LOG")"
  fails=$((fails + 1))
else
  echo "  PASS  countdown abandoned, no poweroff"
fi

if grep -q "countdown abandoned" "$HOME/.cache/yubilock.log"; then
  echo "  PASS  logged the reason"
else
  echo "  FAIL  no log entry explaining the abort"; fails=$((fails + 1))
fi

echo
[ "$fails" -eq 0 ] && echo "suspend-guard: all checks passed" || echo "suspend-guard: $fails FAILED"
exit "$fails"
