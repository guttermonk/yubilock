{
  description = "Respond to YubiKey removal: lock, then optionally power off or hibernate";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # Linux only: the scripts need lsusb, systemd and logind.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The modules take pkgs from the configuration importing them, so nothing
      # here pins nixpkgs for a consumer. The input above is used only by the
      # checks below.
      homeManagerModules = rec {
        yubilock = ./yubilock.nix;
        default = yubilock;
      };

      nixosModules = rec {
        # The privileged poweroff helper. Optional, and separate because it
        # needs CAP_SYS_BOOT, which a user service cannot have.
        yubilock-poweroff = ./yubilock-system.nix;
        default = yubilock-poweroff;
      };

      checks = forAllSystems (pkgs:
        let
          lib = pkgs.lib;

          # Which configurations the module accepts, which its assertions
          # reject, and what lands in the generated config file.
          results = import ./tests/eval.nix { inherit pkgs; };

          # Every attribute ending in _ok must be true.
          notOk = lib.attrNames
            (lib.filterAttrs (name: value: lib.hasSuffix "_ok" name && value != true) results);

          # These two must each come back as a non-empty list of assertion
          # messages - an empty list means the module stopped rejecting a
          # configuration it is supposed to reject.
          missingAssertions = lib.filter (name: results.${name} == [ ])
            [ "hibernateThenPoweroff" "bothNull" ];

          problems =
            (map (name: "${name} is not true") notOk)
            ++ (map (name: "${name} returned no assertion messages") missingAssertions);
        in
        {
          # Builds all four packaged scripts, so a syntax error or a missing
          # runtime dependency fails here rather than when the key comes out.
          packages = import ./tests/packages.nix { inherit pkgs; };

          module-eval = pkgs.runCommand "yubilock-module-eval" { } (
            if problems == [ ] then
              "echo 'module eval: all checks passed' > $out"
            else
              ''
                ${lib.concatMapStringsSep "\n" (p: "echo '  FAIL  ${p}'") problems}
                exit 1
              ''
          );
        });
    };
}
