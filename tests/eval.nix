# Module-level tests: which configurations evaluate, which the assertions
# reject, and what ends up in the generated config file.
#
#   nix-instantiate --eval --strict --json tests/eval.nix
#
# Every attribute ending in _ok must be true; hibernateThenPoweroff and
# bothNull must each return a non-empty list of assertion messages.
{ pkgs ? import <nixpkgs> { } }:

let
  lib = pkgs.lib;

  # Minimal stand-ins for the home-manager options the module writes to, so
  # this evaluates without home-manager in scope.
  hmStubs = { lib, ... }: {
    options = {
      xdg.configFile = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
      };
      systemd.user.services = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      home.packages = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
      };
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
      };
    };
  };

  eval = settings: lib.evalModules {
    modules = [
      hmStubs
      ../yubilock.nix
      { _module.args.pkgs = pkgs; }
      { services.yubilock = settings; }
    ];
  };

  # Collect assertion failures the way NixOS and home-manager do.
  failures = settings:
    let c = (eval settings).config;
    in map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);

  configText = settings: (eval settings).config.xdg.configFile."yubilock/config".text;

in {
  # --- must evaluate cleanly ---
  default_ok         = failures { enable = true; } == [ ];
  lockThenPoweroff_ok = failures { enable = true; secondaryAction = "poweroff"; } == [ ];
  canary_ok          = failures { enable = true; primaryAction = null; secondaryAction = "poweroff"; } == [ ];
  immediatePoweroff_ok = failures { enable = true; primaryAction = "poweroff"; } == [ ];
  immediateHibernate_ok = failures { enable = true; primaryAction = "hibernate"; } == [ ];
  lockThenHibernate_ok = failures { enable = true; secondaryAction = "hibernate"; } == [ ];
  zeroGrace_ok       = failures { enable = true; primaryAction = null; gracePeriod = 0; secondaryAction = "poweroff"; } == [ ];

  # --- must be rejected, with a message naming the rewrite ---
  hibernateThenPoweroff = failures {
    enable = true;
    primaryAction = "hibernate";
    gracePeriod = 10;
    secondaryAction = "poweroff";
  };
  bothNull = failures { enable = true; primaryAction = null; secondaryAction = null; };

  # --- generated config file ---
  defaultConfigText = configText { enable = true; };
  canaryConfigText = configText {
    enable = true;
    primaryAction = null;
    gracePeriod = 60;
    secondaryAction = "poweroff";
    notify = {
      enable = true;
      title = "Coalmine Canary";
      message = "The canary will no longer sing";
    };
  };
  # Quoting hazard: shell metacharacters in free-text options must land inert.
  nastyConfigText = configText {
    enable = true;
    secondaryAction = "poweroff";
    notify = {
      enable = true;
      title = "it's \"fine\"";
      message = "$(touch /tmp/pwned) `id`";
    };
  };
}
