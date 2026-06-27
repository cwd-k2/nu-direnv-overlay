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
        packages.default = pkgs.callPackage ./nix/package.nix { };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/nu-direnv-overlay";
          meta.description = "Project-local Nushell overlays managed by direnv";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.direnv
            pkgs.nushell
            self.packages.${system}.default
          ];
        };

        checks.default = pkgs.runCommand "nu-direnv-overlay-check" { } ''
          set -eu
          pkg=${self.packages.${system}.default}
          export HOME="$TMPDIR/home"
          export XDG_CONFIG_HOME="$TMPDIR/config"
          export XDG_DATA_HOME="$TMPDIR/data"
          export XDG_CACHE_HOME="$TMPDIR/cache"
          mkdir -p "$HOME" "$XDG_CONFIG_HOME/direnv" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

          test -x "$pkg/bin/nu-direnv-overlay"
          test -f "$pkg/share/direnv/lib/nu-overlay.sh"
          test -f "$pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"

          ${pkgs.direnv}/bin/direnv stdlib > "$TMPDIR/stdlib.sh"
          . "$pkg/share/direnv/lib/nu-overlay.sh"
          type use_nu-overlay >/dev/null

          ${pkgs.nushell}/bin/nu --no-config-file --commands \
            'source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"; nu-direnv-overlay status | ignore'

          printf 'source %q\n' "$pkg/share/direnv/lib/nu-overlay.sh" > "$XDG_CONFIG_HOME/direnv/direnvrc"
          mkdir -p "$TMPDIR/project/overlay"
          cat > "$TMPDIR/project/.envrc" <<'EOF'
          use nu-overlay overlay/task.nu
          use nu-overlay overlay/git.nu
          EOF
          cat > "$TMPDIR/project/overlay/task.nu" <<'EOF'
          export def build [] { "built" }
          EOF
          cat > "$TMPDIR/project/overlay/git.nu" <<'EOF'
          export def st [] { "status" }
          EOF

          (
            cd "$TMPDIR/project"
            ${pkgs.direnv}/bin/direnv allow . >/dev/null
          )

          apply=$(
            cd "$TMPDIR/project"
            ${pkgs.nushell}/bin/nu --no-config-file --commands \
              '${pkgs.direnv}/bin/direnv export json | from json | get DIRENV_NU_OVERLAY_APPLY'
          )
          test -f "$apply"

          cat > "$TMPDIR/apply-test.nu" <<EOF
          const apply = '$apply'
          source \$apply
          if (build) != "built" { error make { msg: "build command did not load" } }
          if (st) != "status" { error make { msg: "st command did not load" } }
          if not ((overlay list | where name =~ '^nu-direnv-' | is-not-empty)) {
            error make { msg: "nu-direnv overlay names were not created" }
          }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/apply-test.nu"

          touch "$out"
        '';
      }
    )
    // {
      overlays.default = final: _prev: {
        nu-direnv-overlay = final.callPackage ./nix/package.nix { };
      };

      nixosModules.default = import ./nix/nixos-module.nix self;
      homeManagerModules.default = import ./nix/home-manager-module.nix self;
    };
}
