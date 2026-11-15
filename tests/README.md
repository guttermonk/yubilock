# Tests

Yubilock's failure mode is a machine that powers off when it shouldn't, or one
that quietly stops protecting you while the indicator still reads ON. Neither is
pleasant to discover by hand, so the behaviour is exercised against stubbed
system tools instead: a fake `lsusb` whose answer the test controls, and a
`systemctl`/`loginctl` that log what they were asked to do rather than doing it.

Nothing here can lock your session or power off your machine.

## Shell suites

```bash
bash tests/run-all.sh          # all four
bash tests/state-machine.sh    # or individually
```

| Suite | Covers |
|---|---|
| `state-machine.sh` | Removal end to end: lock then poweroff, cancel by reinserting, cancel by toggling off, the canary config, a machine with no config file, immediate poweroff, and the `-ff` → helper unit → `-i` fallback chain |
| `suspend-guard.sh` | A suspend/resume mid-countdown abandons the countdown instead of firing against a stale timer. Uses a `date` stub that can be shoved an hour forward |
| `toggle.sh` | The toggle drives systemd when the user unit exists and only backgrounds the monitor when it doesn't — getting this wrong leaves two monitors racing on one state file |
| `cache-dir.sh` | All four scripts create `~/.cache` themselves on a machine that has no such directory. A script that cannot write its state file reads back `off` next run, which looks exactly like yubilock having been switched off on purpose |

Each exits non-zero with a count of failed checks, so they drop straight into
CI or a pre-commit hook.

They take roughly a minute in total, most of it real `sleep` waiting on grace
periods.

## Nix tests

Both of these run from the flake, against its pinned nixpkgs:

```bash
nix flake check
```

That builds `checks.module-eval` (every `_ok` attribute of `eval.nix` true, and
both assertion cases still rejecting) and `checks.packages` (all four scripts
build). It does not run the shell suites above — they take over a minute of real
`sleep` and background processes, so they stay a separate command.

To run them by hand instead, they need a nixpkgs. With a channel configured,
`<nixpkgs>` resolves on its own; otherwise point them at one explicitly.

`eval.nix` is a function, and `nix-instantiate --eval` hands back the function
itself rather than calling it, so import and apply it yourself:

```bash
nix-instantiate --eval --strict --json --expr 'import ./tests/eval.nix { }'
nix-build tests/packages.nix

# offline, or pinning a specific tree:
nix-instantiate --eval --strict --json \
  --expr 'import ./tests/eval.nix { pkgs = import /path/to/nixpkgs { }; }'
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
