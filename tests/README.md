# Tests

Yubilock's failure mode is a machine that powers off when it shouldn't, or one
that quietly stops protecting you while the indicator still reads ON. Neither is
pleasant to discover by hand, so the behaviour is exercised against stubbed
system tools instead: a fake `lsusb` whose answer the test controls, and a
`systemctl`/`loginctl` that log what they were asked to do rather than doing it.

Nothing here can lock your session or power off your machine.

## Shell suites

```bash
bash tests/run-all.sh          # all three
bash tests/state-machine.sh    # or individually
```

| Suite | Covers |
|---|---|
| `state-machine.sh` | Removal end to end: lock then poweroff, cancel by reinserting, cancel by toggling off, the canary config, a machine with no config file, immediate poweroff, and the `-ff` → helper unit → `-i` fallback chain |
| `suspend-guard.sh` | A suspend/resume mid-countdown abandons the countdown instead of firing against a stale timer. Uses a `date` stub that can be shoved an hour forward |
| `toggle.sh` | The toggle drives systemd when the user unit exists and only backgrounds the monitor when it doesn't — getting this wrong leaves two monitors racing on one state file |

Each exits non-zero with a count of failed checks, so they drop straight into
CI or a pre-commit hook.

They take roughly a minute in total, most of it real `sleep` waiting on grace
periods.

## Nix tests

These need a nixpkgs. With a channel configured, `<nixpkgs>` resolves on its
own; otherwise point them at one explicitly.

```bash
nix-instantiate --eval --strict --json tests/eval.nix
nix-build tests/packages.nix

# offline, or pinning a specific tree:
nix-instantiate --eval --strict --json tests/eval.nix \
  --arg pkgs 'import /path/to/nixpkgs {}'
```

`eval.nix` checks which configurations the module accepts, which the assertions
reject, and what lands in the generated `~/.config/yubilock/config`. Every
attribute ending in `_ok` must be `true`; `hibernateThenPoweroff` and
`bothNull` must each come back as a non-empty list of assertion messages. It
also feeds `$(touch /tmp/pwned)` through `notify.message` to confirm shell
metacharacters in free-text options land inert.

`packages.nix` builds all four packaged scripts, so a syntax error or a missing
runtime dependency surfaces at build time. The result runs with no inherited
environment at all:

```bash
env -i HOME=$(mktemp -d) ./result/bin/yubikey-status
```

## What isn't covered

The terminal actions themselves. `systemctl poweroff` and `systemctl hibernate`
are stubbed everywhere, by design — a test suite that could power off the
machine running it is worse than no test suite. Those are single lines in
`do_action()` and are verified by reading.

Also untested: real USB hotplug (the tests toggle a flag file instead of a
device), and whether Waybar actually repaints on `SIGRTMIN+5`, which depends on
`signal = 5` being present in your bar config.
