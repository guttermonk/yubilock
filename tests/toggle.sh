#!/usr/bin/env bash
#
# The toggle must drive systemd when the user unit exists, and only fall back
# to a background process when it does not. Getting this wrong leaves an
# unmanaged monitor racing the one systemd starts on next login.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT

mkdir -p "$BASE/bin" "$BASE/home/.cache"
export HOME="$BASE/home"
export ACTION_LOG="$BASE/actions.log"
export UNIT_EXISTS="$BASE/unit_exists"

# `systemctl cat` succeeds only when we say the unit file exists - the same
# question the toggle asks to decide which install it is running under.
cat > "$BASE/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$ACTION_LOG"
case "$*" in
  *"cat yubilock.service"*) [ -f "$UNIT_EXISTS" ] && exit 0 || exit 1 ;;
esac
exit 0
EOF

# Stand-in for a packaged `yubilock` on PATH.
cat > "$BASE/bin/yubilock" <<'EOF'
#!/bin/sh
echo "monitor-started-directly" >> "$ACTION_LOG"
sleep 30
EOF

chmod +x "$BASE"/bin/*
export PATH="$BASE/bin:$PATH"

fails=0
run_toggle() { : > "$ACTION_LOG"; bash "$REPO/scripts/yubilock-toggle.sh" > /dev/null 2>&1; }

check() { # description, pattern, expected match y/n
  if grep -q "$2" "$ACTION_LOG"; then got=y; else got=n; fi
  if [ "$got" = "$3" ]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1 (expected match=$3, got=$got)"
    echo "        actions: $(tr '\n' '|' < "$ACTION_LOG")"
    fails=$((fails + 1))
  fi
}

check_state() { # description, expected
  if [ "$(cat "$HOME/.cache/yubilock-state")" = "$2" ]; then
    echo "  PASS  $1"
  else
    echo "  FAIL  $1 (state is $(cat "$HOME/.cache/yubilock-state"))"
    fails=$((fails + 1))
  fi
}

echo "== module install (unit exists) =="
touch "$UNIT_EXISTS"

echo "off" > "$HOME/.cache/yubilock-state"
run_toggle
check "turning on uses systemd"        "systemctl --user start yubilock.service" y
check "does NOT spawn a stray monitor" "monitor-started-directly"                n
check_state "state file now on" "on"

run_toggle
check "turning off uses systemd" "systemctl --user stop yubilock.service" y
check_state "state file now off" "off"

echo "== manual install (no unit) =="
rm -f "$UNIT_EXISTS"

echo "off" > "$HOME/.cache/yubilock-state"
run_toggle
sleep 1
check "falls back to running the monitor" "monitor-started-directly"                y
check "no systemd start attempted"        "systemctl --user start yubilock.service" n

pkill -f "bin/yubilock$" 2>/dev/null

echo
[ "$fails" -eq 0 ] && echo "toggle: all checks passed" || echo "toggle: $fails FAILED"
exit "$fails"
