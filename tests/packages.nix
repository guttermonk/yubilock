# Builds every script the module packages, so a syntax error or a missing
# runtime dependency fails at build time rather than the moment your YubiKey
# comes out.
#
#   nix-build tests/packages.nix
#
# The result's bin/ holds yubilock, yubikey-status, yubilock-toggle and
# yubilock-restore, each with its dependencies wrapped into PATH. They run
# with no inherited environment:
#
#   env -i HOME=$(mktemp -d) ./result/bin/yubikey-status
{ pkgs ? import <nixpkgs> { } }:

let
  lib = pkgs.lib;

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

  config = (lib.evalModules {
    modules = [
      hmStubs
      ../yubilock.nix
      { _module.args.pkgs = pkgs; }
      {
        services.yubilock = {
          enable = true;
          secondaryAction = "poweroff";
        };
      }
    ];
  }).config;

in pkgs.buildEnv {
  name = "yubilock-test-env";
  paths = config.home.packages;
}
