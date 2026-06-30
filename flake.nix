{
  description = "Project-local Nushell overlays managed by direnv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Build/install the package from the same derivation used by modules and
        # profile installs.
        packages.default = pkgs.callPackage ./nix/package.nix { };

        # Expose the helper CLI as the default app for quick `nix run` checks.
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/nu-direnv-overlay";
          meta.description = "Project-local Nushell overlays managed by direnv";
        };

        # Development shell intentionally stays small: runtime tools plus the
        # package under test.
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.direnv
            pkgs.nushell
            self.packages.${system}.default
          ];
        };

        # The test runner lives in tests/ so the flake output definition stays
        # focused on wiring package paths into the test environment.
        checks.default = pkgs.runCommand "nu-direnv-overlay-check" { } ''
          set -eu
          export PKG="${self.packages.${system}.default}"
          export NU="${pkgs.nushell}/bin/nu"
          export DIRENV="${pkgs.direnv}/bin/direnv"
          export EXPECT="${pkgs.expect}/bin/expect"
          export TEST_DIR="${./tests}"

          ${pkgs.bash}/bin/bash ${./tests/run.bash}

          # runCommand outputs must create $out on success.
          touch "$out"
        '';
      }
    )
    // {
      # Consumers can import this overlay to get the package in their nixpkgs.
      overlays.default = final: _prev: {
        nu-direnv-overlay = final.callPackage ./nix/package.nix { };
      };

      # Keep module exports outside eachDefaultSystem because NixOS/Home Manager
      # modules are not system-specific flake outputs.
      nixosModules.default = import ./nix/nixos-module.nix self;
      homeManagerModules.default = import ./nix/home-manager-module.nix self;
    };
}
