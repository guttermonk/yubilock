{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.yubilock;

  # Actions that never hand control back to the monitoring script. A secondary
  # action queued behind one of these could never run.
  terminalActions = [ "poweroff" "hibernate" ];
  isTerminal = a: a != null && elem a terminalActions;

  # The shell sees "null" as an empty string.
  actionStr = a: if a == null then "" else a;
  actionName = a: if a == null then "null" else a;

  # Defined in scripts.nix so the flake's `packages` output builds the same
  # derivations this module installs, rather than a second copy of them.
  scripts = import ./scripts.nix { inherit pkgs; };

  monitorPkg = scripts.yubilock;
  statusPkg = scripts.yubikey-status;
  togglePkg = scripts.yubilock-toggle;
  restorePkg = scripts.yubilock-restore;

in {
  options.services.yubilock = {
    enable = mkEnableOption "YubiKey removal monitor";

    autoRestore = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically restore yubilock state on login.
        If enabled, the yubilock service will be restarted on login
        if it was running when you last logged out.
      '';
    };

    primaryAction = mkOption {
      type = types.nullOr (types.enum [ "lock" "poweroff" "hibernate" ]);
      default = "lock";
      description = ''
        What happens the moment the YubiKey is removed.

        `null` does nothing immediately, which only makes sense alongside a
        `secondaryAction` — it leaves the session usable during the grace
        period. Note that this also leaves the Waybar toggle reachable, so
        anyone holding the machine can switch yubilock off before the
        secondary action fires.

        `poweroff` and `hibernate` end the session, so nothing can follow
        them; set `secondaryAction = null` when using either here.
      '';
    };

    gracePeriod = mkOption {
      type = types.ints.unsigned;
      default = 60;
      description = ''
        Seconds between the primary and secondary actions. Reinserting the
        YubiKey during this window cancels the secondary action, as does
        switching yubilock off.

        Has no effect when `secondaryAction` is null. Set to 0 for a
        secondary action with no cancellation window.
      '';
    };

    secondaryAction = mkOption {
      type = types.nullOr (types.enum [ "lock" "poweroff" "hibernate" ]);
      default = null;
      description = ''
        What happens once the grace period elapses without the YubiKey
        coming back. `null` means nothing does — removal triggers only the
        primary action, which is yubilock's original behaviour.

        This is the option that takes the disk out of its decrypted state.
        A root LUKS volume cannot be closed while you are running on it, so
        `poweroff` is what actually re-encrypts it; `hibernate` does too,
        but has to write all of RAM to swap first and is correspondingly
        slower to take effect.
      '';
    };

    monitorCommand = mkOption {
      type = types.str;
      readOnly = true;
      default = "${monitorPkg}/bin/yubilock";
      description = "Path to the packaged monitor. Read-only.";
    };

    statusCommand = mkOption {
      type = types.str;
      readOnly = true;
      default = "${statusPkg}/bin/yubikey-status";
      description = ''
        Path to the packaged Waybar status script. Read-only — reference it
        from your Waybar configuration rather than hardcoding a path:

          exec = config.services.yubilock.statusCommand;
      '';
    };

    toggleCommand = mkOption {
      type = types.str;
      readOnly = true;
      default = "${togglePkg}/bin/yubilock-toggle";
      description = ''
        Path to the packaged Waybar toggle script. Read-only:

          on-click = config.services.yubilock.toggleCommand;
      '';
    };

    notify = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Send a desktop notification when the YubiKey is removed.

          Off by default: with the usual `primaryAction = "lock"` the screen
          is already locked by the time it would appear, and most lockers
          hide notifications anyway.

          It earns its place in configurations where the session stays
          usable during the grace period, where a deliberately unremarkable
          message can tell you yubilock has started without announcing to
          anyone else what is about to happen.
        '';
      };

      title = mkOption {
        type = types.str;
        default = "Yubilock";
        description = "Notification title.";
      };

      message = mkOption {
        type = types.str;
        default = "YubiKey removed.";
        description = "Notification body.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secondaryAction == null || !(isTerminal cfg.primaryAction);
        message = ''
          services.yubilock: primaryAction = "${actionName cfg.primaryAction}" ends the
          session, so secondaryAction = "${actionName cfg.secondaryAction}" can never run.

          For an immediate ${actionName cfg.primaryAction} and nothing else:
            primaryAction = "${actionName cfg.primaryAction}";
            secondaryAction = null;

          For a cancellable grace period first:
            primaryAction = null;  # or "lock"
            gracePeriod = 60;
            secondaryAction = "${actionName cfg.primaryAction}";
        '';
      }
      {
        assertion = !(cfg.primaryAction == null && cfg.secondaryAction == null);
        message = ''
          services.yubilock: both primaryAction and secondaryAction are null,
          so the service would monitor the YubiKey and then do nothing.
        '';
      }
    ];

    # Consumed by scripts/yubilock.sh and scripts/yubikey-status.sh, so the
    # Waybar indicator and the monitor always agree on the configuration.
    xdg.configFile."yubilock/config".text = ''
      # Generated by services.yubilock — edit your Nix configuration instead.
      YUBILOCK_PRIMARY_ACTION=${escapeShellArg (actionStr cfg.primaryAction)}
      YUBILOCK_GRACE_PERIOD=${toString cfg.gracePeriod}
      YUBILOCK_SECONDARY_ACTION=${escapeShellArg (actionStr cfg.secondaryAction)}
      YUBILOCK_NOTIFY=${escapeShellArg (boolToString cfg.notify.enable)}
      YUBILOCK_NOTIFY_TITLE=${escapeShellArg cfg.notify.title}
      YUBILOCK_NOTIFY_MESSAGE=${escapeShellArg cfg.notify.message}
    '';

    systemd.user.services.yubilock = {
      Unit = {
        Description = "YubiKey removal monitor";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = cfg.monitorCommand;
        Restart = "on-failure";
        RestartSec = "5s";
        # No ExecStartPre creating ~/.cache: the scripts do that themselves, so
        # the toggle and the status indicator get it too — they run from Waybar,
        # not from this unit.
        #
        # No ExecStopPost resetting the state file: it would overwrite the
        # saved state on every logout, leaving autoRestore nothing to restore.
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    systemd.user.services.yubilock-restore = mkIf cfg.autoRestore {
      Unit = {
        Description = "Restore YubiKey monitor state on login";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${restorePkg}/bin/yubilock-restore";
        RemainAfterExit = false;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    # Packaged with their dependencies wrapped in, so there is nothing to copy
    # into ~/.config/waybar/scripts and nothing to keep in sync by hand.
    home.packages = [ monitorPkg statusPkg togglePkg restorePkg ];
  };
}
