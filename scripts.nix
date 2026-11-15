# The four packaged scripts, as derivations.
#
# Kept out of yubilock.nix so the flake's `packages` output and a module install
# build the same thing — `nix run` cannot drift from what lands on your PATH
# through Home Manager, because there is only one definition.
#
#   nix-build scripts.nix -A yubikey-status
{ pkgs }:

let
  inherit (pkgs.lib) makeBinPath;

  runtimeDeps = with pkgs; [
    usbutils    # lsusb
    gnugrep
    gawk
    coreutils
    procps      # pkill, ps
    systemd     # systemctl, loginctl
    libnotify   # notify-send
  ];

  # The module and the manual install run byte-identical logic — each script is
  # read from scripts/ rather than duplicated here, so the two install paths
  # cannot drift apart.
  #
  # writeShellScriptBin rather than writeShellApplication: the latter imposes
  # `set -euo pipefail`, and fail-fast is the wrong posture for a security
  # monitor. A stray non-zero exit from `pkill` or a missing config file would
  # kill the process, leaving you unprotected while the indicator still reads
  # ON. These scripts are written to keep running instead.
  mkScript = name: file: extraDeps:
    pkgs.writeShellScriptBin name ''
      export PATH="${makeBinPath (runtimeDeps ++ extraDeps)}:$PATH"
      ${builtins.readFile file}
    '';

in
rec {
  yubilock = mkScript "yubilock" ./scripts/yubilock.sh [ ];
  yubikey-status = mkScript "yubikey-status" ./scripts/yubikey-status.sh [ ];

  # The toggle shells out to the monitor on non-systemd installs, so it needs
  # to be able to find it.
  yubilock-toggle = mkScript "yubilock-toggle" ./scripts/yubilock-toggle.sh [ yubilock ];

  yubilock-restore = mkScript "yubilock-restore" ./scripts/yubilock-restore.sh [ ];
}
