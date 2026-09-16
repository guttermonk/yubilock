{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.yubilock-poweroff;

  # `systemctl poweroff -ff` bypasses the system manager and calls
  # reboot(RB_POWER_OFF) directly. That is the fastest shutdown the kernel
  # offers, but it needs CAP_SYS_BOOT, which the yubilock user service does
  # not have — hence this root-owned helper.
  #
  # The sync is best-effort and time-boxed: flushing dirty pages is worth a
  # moment, but blocking on a wedged filesystem would defeat the point of
  # using the hard path in the first place.
  hardPoweroff = pkgs.writeShellScript "yubilock-hard-poweroff" ''
    ${pkgs.coreutils}/bin/timeout 2 ${pkgs.coreutils}/bin/sync || true
    exec ${pkgs.systemd}/bin/systemctl poweroff --force --force
  '';

in {
  options.services.yubilock-poweroff = {
    enable = mkEnableOption ''
      the privileged yubilock power-off helper.

      Without it, yubilock falls back to `systemctl poweroff -i`, which still
      overrides inhibitor locks but performs an orderly shutdown that a hung
      unit can delay by up to DefaultTimeoutStopSec
    '';

    allowedGroup = mkOption {
      type = types.str;
      default = "wheel";
      description = ''
        Group permitted to trigger the immediate power off without
        authentication.

        Be deliberate here: this grants every member a passwordless, instant,
        unclean shutdown of the machine. That is the intended behaviour for
        yubilock, but it is a wider capability than `sudo poweroff` on a
        system where sudo requires a password.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.yubilock-poweroff = {
      description = "Immediate power off (yubilock)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hardPoweroff}";
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "yubilock-poweroff.service" &&
            action.lookup("verb") == "start" &&
            subject.isInGroup("${cfg.allowedGroup}")) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
