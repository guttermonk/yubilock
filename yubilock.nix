{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.yubilock;
  
  # Script paths - users should copy scripts to their ~/.config/waybar/scripts/
  yubilockScript = pkgs.writeShellScript "yubilock" ''
    STATE_FILE="$HOME/.cache/yubilock-state"
    LOG_FILE="$HOME/.cache/yubilock.log"
    PID_FILE="$HOME/.cache/yubilock.pid"

    # Function to check if a YubiKey is currently plugged in
    check_yubikey() {
        if ${pkgs.usbutils}/bin/lsusb | ${pkgs.gnugrep}/bin/grep -i "yubikey" > /dev/null; then
            return 0 # device is present
        else
            return 1 # device is not present
        fi
    }

    # Function to lock the screen
    lock_screen() {
        # Using loginctl for systemd-based systems
        ${pkgs.systemd}/bin/loginctl lock-session
        echo "Screen locked at $(date)" >> "$LOG_FILE"
    }

    # Create state file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
        echo "off" > "$STATE_FILE"
    fi

    # Record PID for later termination
    echo "$$" > "$PID_FILE"

    # Main monitoring loop
    echo "YubiKey monitoring started at $(date)" >> "$LOG_FILE"

    while true; do
        # Check if monitoring is still enabled
        if [ "$(cat "$STATE_FILE")" != "on" ]; then
            echo "YubiKey monitoring stopped at $(date)" >> "$LOG_FILE"
            exit 0
        fi

        if check_yubikey; then
            echo "YubiKey detected at $(date)" >> "$LOG_FILE"

            # Wait until the YubiKey is removed
            while check_yubikey && [ "$(cat "$STATE_FILE")" = "on" ]; do
                sleep 1
            done

            # If we exited because service was disabled, exit gracefully
            if [ "$(cat "$STATE_FILE")" != "on" ]; then
                echo "YubiKey monitoring stopped at $(date)" >> "$LOG_FILE"
                exit 0
            fi

            echo "YubiKey removed at $(date)" >> "$LOG_FILE"
            lock_screen
        else
            echo "No YubiKey detected. Checking again in 10 seconds..." >> "$LOG_FILE"
            # Check less frequently to reduce system load
            sleep 10
        fi
    done
  '';

  yubilockRestoreScript = pkgs.writeShellScript "yubilock-restore" ''
    STATE_FILE="$HOME/.cache/yubilock-state"
    LOG_FILE="$HOME/.cache/yubilock-restore.log"
    
    echo "[$(date)] Checking yubilock state on login" >> "$LOG_FILE"
    
    # Create state file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
        echo "off" > "$STATE_FILE"
        echo "[$(date)] No state file found, defaulting to off" >> "$LOG_FILE"
        exit 0
    fi
    
    # Read the saved state
    saved_state=$(cat "$STATE_FILE")
    echo "[$(date)] Saved state: $saved_state" >> "$LOG_FILE"
    
    # If it was enabled before, re-enable it
    if [ "$saved_state" = "on" ]; then
        if ! ${pkgs.systemd}/bin/systemctl --user is-active yubilock.service > /dev/null 2>&1; then
            echo "[$(date)] Restoring yubilock service" >> "$LOG_FILE"
            ${pkgs.systemd}/bin/systemctl --user start yubilock.service
            echo "[$(date)] Yubilock service restored" >> "$LOG_FILE"
        else
            echo "[$(date)] Yubilock service already running" >> "$LOG_FILE"
        fi
    fi
  '';

in {
  options.services.yubilock = {
    enable = mkEnableOption "YubiKey screen lock monitor";

    autoRestore = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically restore yubilock state on login.
        If enabled, the yubilock service will be restarted on login
        if it was running when you last logged out.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Systemd user service for yubilock
    systemd.user.services.yubilock = {
      Unit = {
        Description = "YubiKey lock screen monitor";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${yubilockScript}";
        Restart = "on-failure";
        RestartSec = "5s";
        # Ensure state persists
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.cache";
        # Clean state on stop
        ExecStopPost = "${pkgs.bash}/bin/bash -c 'echo off > %h/.cache/yubilock-state'";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
    
    # Systemd user service to restore yubilock state on login
    systemd.user.services.yubilock-restore = mkIf cfg.autoRestore {
      Unit = {
        Description = "Restore YubiKey monitor state on login";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${yubilockRestoreScript}";
        RemainAfterExit = false;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    # Ensure required packages are available
    home.packages = with pkgs; [
      usbutils  # for lsusb command
    ];
  };
}
