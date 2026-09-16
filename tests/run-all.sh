#!/usr/bin/env bash
#
# Runs the three shell suites. The Nix tests need a nixpkgs and are run
# separately - see tests/README.md.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

total=0
for suite in state-machine.sh suspend-guard.sh toggle.sh; do
    echo "### $suite"
    bash "$suite"
    total=$((total + $?))
    echo
done

if [ "$total" -eq 0 ]; then
    echo "all suites passed"
else
    echo "$total check(s) FAILED"
fi
exit "$total"
