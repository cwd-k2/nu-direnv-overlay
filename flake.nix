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

          (
            cd "$TMPDIR/project"
            ${pkgs.direnv}/bin/direnv export json > "$TMPDIR/inherited.json"
          )
          cat > "$TMPDIR/inherited-reload.nu" <<EOF
          open "$TMPDIR/inherited.json" | load-env
          \$env.PATH = (\$env.PATH | prepend "${pkgs.direnv}/bin")
          source "$pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
          __nu-direnv-overlay export-direnv
          nu-direnv-overlay status | get apply
          EOF
          hook_apply=$(
            cd "$TMPDIR/project"
            ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/inherited-reload.nu"
          )
          test -f "$hook_apply"

          cat > "$TMPDIR/hook-apply-test.nu" <<EOF
          const apply = '$hook_apply'
          source \$apply
          if (build) != "built" { error make { msg: "build command did not reload from inherited direnv state in hook path" } }
          if (st) != "status" { error make { msg: "st command did not reload from inherited direnv state in hook path" } }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/hook-apply-test.nu"

          cat > "$TMPDIR/inherited-force-reload.nu" <<EOF
          open "$TMPDIR/inherited.json" | load-env
          \$env.PATH = (\$env.PATH | prepend "${pkgs.direnv}/bin")
          source "$pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
          nu-direnv-overlay reload
          nu-direnv-overlay status | get apply
          EOF
          reloaded_apply=$(
            cd "$TMPDIR/project"
            ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/inherited-force-reload.nu"
          )
          test -f "$reloaded_apply"

          cat > "$TMPDIR/reloaded-apply-test.nu" <<EOF
          const apply = '$reloaded_apply'
          source \$apply
          if (build) != "built" { error make { msg: "build command did not reload from inherited direnv state" } }
          if (st) != "status" { error make { msg: "st command did not reload from inherited direnv state" } }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/reloaded-apply-test.nu"

          stale_cleanup=$(
            ${pkgs.nushell}/bin/nu --no-config-file --commands '
              source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
              const apply = "'"$reloaded_apply"'"
              source $apply
              hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
              hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
              __nu-direnv-overlay write-source
              $nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu"
            '
          )
          if ! grep -q 'overlay hide --keep-env \[ PWD \] "nu-direnv-' "$stale_cleanup"; then
            echo "cleanup did not include active nu-direnv overlay" >&2
            cat "$stale_cleanup" >&2
            exit 1
          fi

          cat > "$TMPDIR/stale-cleanup-test.nu" <<EOF
          const apply = '$reloaded_apply'
          const cleanup = '$stale_cleanup'
          source \$apply
          cd "$TMPDIR"
          source \$cleanup
          if \$env.PWD != "$TMPDIR" {
            error make { msg: "cleanup changed PWD while hiding overlay" }
          }
          if ((overlay list | where name =~ '^nu-direnv-' and active == true | is-not-empty)) {
            error make { msg: "nu-direnv overlay remained active after stale cleanup" }
          }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/stale-cleanup-test.nu"

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
