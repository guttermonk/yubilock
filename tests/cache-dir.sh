#!/usr/bin/env bash
#
# Every script that keeps state has to create ~/.cache itself. The directory is
# not guaranteed to exist, and the service unit cannot stand in for the scripts:
# the toggle and the status indicator run from Waybar, the restore oneshot runs
# from its own unit, so three of the four paths never touch it.
#
# A script that cannot write its state file reads back "off" on the next run,
# which is indistinguishable from yubilock having been switched off on purpose.
# That is the failure worth a suite of its own - protection quietly absent, with
# the indicator agreeing that everything is fine.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$(mktemp -d)"
trap 'kill "${MON:-}" 2>/dev/null; rm -rf "$BASE"' EXIT

mkdir -p "$BASE/bin"
export YK_FLAG="$BASE/yubikey_present"
export ACTION_LOG="$BASE/actions.log"
touch "$YK_FLAG"
: > "$ACTION_LOG"

cat > "$BASE/bin/lsusb" <<'EOF'
#!/bin/sh
if [ -f "$YK_FLAG" ]; then
  echo "Bus 001 Device 005: ID 1050:0407 Yubico.com Yubikey 4 OTP+U2F+CCID"
else
  echo "Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub"
fi
EOF

# `cat` succeeds, so every script takes the module-install path and drives
# systemd rather than backgrounding a monitor of its own.
cat > "$BASE/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$ACTION_LOG"
exit 0
EOF

cat > "$BASE/bin/loginctl" <<'EOF'
#!/bin/sh
echo "loginctl $*" >> "$ACTION_LOG"
EOF

printf '#!/bin/sh\nexit 0\n' > "$BASE/bin/pkill"
printf '#!/bin/sh\nexit 0\n' > "$BASE/bin/notify-send"
chmod +x "$BASE"/bin/*
export PATH="$BASE/bin:$PATH"

fails=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1 ($2)"; fails=$((fails + 1)); }

# A HOME with no .cache in it at all - the state this suite exists to cover.
fresh_home() {
  rm -rf "$BASE/home"
  mkdir -p "$BASE/home"
  export HOME="$BASE/home"
  [ -d "$HOME/.cache" ] && fail "precondition: ~/.cache absent" "it already exists"
}

check_created() {
  if [ -d "$HOME/.cache" ]; then
    pass "$1 creates ~/.cache"
  else
    fail "$1 creates ~/.cache" "still missing"
  fi
}

# The old failure was a successful-looking run with redirection errors on
# stderr, so silence is part of the contract and not just cosmetic.
check_quiet() {
  if [ -s "$2" ]; then
    fail "$1 leaves stderr clean" "$(tr '\n' '|' < "$2")"
  else
    pass "$1 leaves stderr clean"
  fi
}

check_state() {
  if [ ! -f "$HOME/.cache/yubilock-state" ]; then
    fail "$1 persists its state" "no state file written"
  elif [ "$(cat "$HOME/.cache/yubilock-state")" = "$2" ]; then
    pass "$1 persists its state ($2)"
  else
    fail "$1 persists its state" "wanted $2, got $(cat "$HOME/.cache/yubilock-state")"
  fi
}

echo "== yubikey-status.sh =="
fresh_home
out="$BASE/status.out"; err="$BASE/status.err"
bash "$REPO/scripts/yubikey-status.sh" > "$out" 2> "$err"
check_created "status"
check_quiet   "status" "$err"
check_state   "status" "off"
if grep -q '"text":' "$out"; then
  pass "status still prints Waybar JSON"
else
  fail "status still prints Waybar JSON" "$(head -1 "$out")"
fi

echo "== yubilock-toggle.sh =="
fresh_home
err="$BASE/toggle.err"
: > "$ACTION_LOG"
bash "$REPO/scripts/yubilock-toggle.sh" > /dev/null 2> "$err"
check_created "toggle"
check_quiet   "toggle" "$err"
check_state   "toggle" "on"
if grep -q "systemctl --user start yubilock.service" "$ACTION_LOG"; then
  pass "toggle still reaches systemd"
else
  fail "toggle still reaches systemd" "$(tr '\n' '|' < "$ACTION_LOG")"
fi

echo "== yubilock-restore.sh =="
fresh_home
err="$BASE/restore.err"
bash "$REPO/scripts/yubilock-restore.sh" > /dev/null 2> "$err"
check_created "restore"
check_quiet   "restore" "$err"
check_state   "restore" "off"
if [ -s "$HOME/.cache/yubilock-restore.log" ]; then
  pass "restore writes its own log"
else
  fail "restore writes its own log" "log empty or absent"
fi

echo "== yubilock.sh =="
# The monitor comes up with no state file, so it records "off" and idles. It
# never arms, which keeps this check away from anything that locks or powers off.
fresh_home
err="$BASE/monitor.err"
bash "$REPO/scripts/yubilock.sh" > /dev/null 2> "$err" &
MON=$!
sleep 2
check_created "monitor"
check_quiet   "monitor" "$err"
check_state   "monitor" "off"
if [ -f "$HOME/.cache/yubilock.pid" ]; then
  pass "monitor records its pid"
else
  fail "monitor records its pid" "no pid file"
fi
kill "$MON" 2>/dev/null
wait "$MON" 2>/dev/null
MON=""

echo
[ "$fails" -eq 0 ] && echo "cache-dir: all checks passed" || echo "cache-dir: $fails FAILED"
exit "$fails"
