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

        # The check builds a synthetic direnv project and exercises the Bash and
        # Nushell halves together. Most failures here are regressions in hook
        # ordering, parser-keyword code generation, or cleanup behavior.
        checks.default = pkgs.runCommand "nu-direnv-overlay-check" { } ''
          set -eu
          pkg=${self.packages.${system}.default}

          # Isolate direnv/Nushell state from the builder environment.
          export HOME="$TMPDIR/home"
          export XDG_CONFIG_HOME="$TMPDIR/config"
          export XDG_DATA_HOME="$TMPDIR/data"
          export XDG_CACHE_HOME="$TMPDIR/cache"
          mkdir -p "$HOME" "$XDG_CONFIG_HOME/direnv" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

          test -x "$pkg/bin/nu-direnv-overlay"
          test -f "$pkg/share/direnv/lib/nu-overlay.sh"
          test -f "$pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"

          # Ensure the direnv-side library defines the .envrc API.
          ${pkgs.direnv}/bin/direnv stdlib > "$TMPDIR/stdlib.sh"
          . "$pkg/share/direnv/lib/nu-overlay.sh"
          type use_nu-overlay >/dev/null

          # Ensure the Nushell-side autoload file can be sourced in a clean shell.
          ${pkgs.nushell}/bin/nu --no-config-file --commands \
            'source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"; nu-direnv-overlay status | ignore'

          # Prompt hooks must be idempotent and ordered. sync writes the wrapper;
          # source evaluates it in the interactive scope.
          ${pkgs.nushell}/bin/nu --no-config-file --commands '
            source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
            $env.config.hooks.env_change = { PWD: [{|before, after| "existing" }] }
            __nu-direnv-overlay install-prompt-hooks
            __nu-direnv-overlay install-prompt-hooks
            let prompt_hooks = ($env.config.hooks.pre_prompt | last 2)
            if (($prompt_hooks.0 != "__nu-direnv-overlay prompt-sync") or (not ($prompt_hooks.1 | str starts-with "source "))) {
              error make { msg: "prompt hooks were not installed in sync/source order" }
            }
          '

          # Synthetic project: two overlay files so cleanup must handle multiple
          # internal overlay names and exported definitions.
          printf 'source %q\n' "$pkg/share/direnv/lib/nu-overlay.sh" > "$XDG_CONFIG_HOME/direnv/direnvrc"
          mkdir -p "$TMPDIR/project/overlay"
          cat > "$TMPDIR/project/.envrc" <<'EOF'
          use nu-overlay overlay/task.nu
          use nu-overlay overlay/git.nu
          EOF
          cat > "$TMPDIR/project/overlay/task.nu" <<'EOF'
          export const project_name = "project"
          export module nested { export def hi [] { "hi" } }
          export def build [] { "built" }
          EOF
          cat > "$TMPDIR/project/overlay/git.nu" <<'EOF'
          export def st [] { "status" }
          EOF
          mkdir -p "$TMPDIR/project-b/overlay"
          cat > "$TMPDIR/project-b/.envrc" <<'EOF'
          export PROJECT_MARK=B
          use nu-overlay overlay/task.nu
          EOF
          cat > "$TMPDIR/project-b/overlay/task.nu" <<'EOF'
          export def build [] { "built-b" }
          export def b_only [] { "b-only" }
          EOF

          (
            cd "$TMPDIR/project"
            ${pkgs.direnv}/bin/direnv allow . >/dev/null
          )
          (
            cd "$TMPDIR/project-b"
            ${pkgs.direnv}/bin/direnv allow . >/dev/null
          )

          # direnv evaluation should produce an apply file path for the parent
          # Nushell hook to consume.
          apply=$(
            cd "$TMPDIR/project"
            ${pkgs.nushell}/bin/nu --no-config-file --commands \
              '${pkgs.direnv}/bin/direnv export json | from json | get DIRENV_NU_OVERLAY_APPLY'
          )
          test -f "$apply"

          # The raw apply file must be valid Nushell and expose project commands.
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

          # Simulate the normal direnv hook loading env before nu-direnv-overlay
          # syncs overlays from the inherited DIRENV_NU_OVERLAY_APPLY value.
          (
            cd "$TMPDIR/project"
            ${pkgs.direnv}/bin/direnv export json > "$TMPDIR/inherited.json"
          )
          (
            cd "$TMPDIR/project-b"
            ${pkgs.direnv}/bin/direnv export json > "$TMPDIR/inherited-b.json"
          )
          cat > "$TMPDIR/inherited-reload.nu" <<EOF
          open "$TMPDIR/inherited.json" | load-env
          \$env.PATH = (\$env.PATH | prepend "${pkgs.direnv}/bin")
          source "$pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
          __nu-direnv-overlay sync-overlays
          nu-direnv-overlay status | get apply
          EOF
          hook_apply=$(
            cd "$TMPDIR/project"
            ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/inherited-reload.nu"
          )
          test -f "$hook_apply"

          # The wrapper produced from inherited direnv state should load the same
          # commands as the raw apply file.
          cat > "$TMPDIR/hook-apply-test.nu" <<EOF
          const apply = '$hook_apply'
          source \$apply
          if (build) != "built" { error make { msg: "build command did not reload from inherited direnv state in hook path" } }
          if (st) != "status" { error make { msg: "st command did not reload from inherited direnv state in hook path" } }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/hook-apply-test.nu"

          # Manual reload is overlay-only: it should resync from current env
          # without calling direnv itself.
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

          # Repeated prompt syncs inside the same project must be a no-op after
          # the apply file is already active. Hiding and re-sourcing the same
          # internal overlay can leave Nushell reporting the module as active
          # while exported commands are hidden and unusable.
          same_project_wrapper=$(
            ${pkgs.nushell}/bin/nu --no-config-file --commands '
              source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
              open "'"$TMPDIR/inherited.json"'" | load-env
              const apply = "'"$reloaded_apply"'"
              source $apply
              __nu-direnv-overlay write-source
              $nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu"
            '
          )
          test -f "$same_project_wrapper"
          test ! -s "$same_project_wrapper"
          cat > "$TMPDIR/same-project-wrapper-test.nu" <<EOF
          const apply = '$reloaded_apply'
          const wrapper = '$same_project_wrapper'
          source "$pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
          open "$TMPDIR/inherited.json" | load-env
          source \$apply
          source \$wrapper
          if (build) != "built" { error make { msg: "same-project prompt sync hid build command" } }
          if (st) != "status" { error make { msg: "same-project prompt sync hid st command" } }
          if ((nu-direnv-overlay status | get active | length) != 2) {
            error make { msg: "unexpected active overlay count after same-project no-op" }
          }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/same-project-wrapper-test.nu"

          # Direct project-to-project movement is different from leaving to an
          # unmanaged directory: cleanup for project A runs while direnv has
          # already loaded project B's environment and apply path. A cleanup must
          # not roll B's env back, and B's apply must replace overlapping command
          # names such as `build`.
          project_to_project_wrapper=$(
            ${pkgs.nushell}/bin/nu --no-config-file --commands '
              source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
              const apply_a = "'"$reloaded_apply"'"
              open "'"$TMPDIR/inherited-b.json"'" | load-env
              source $apply_a
              __nu-direnv-overlay write-source
              $nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu"
            '
          )
          cat > "$TMPDIR/project-to-project-test.nu" <<EOF
          const apply_a = '$reloaded_apply'
          const wrapper = '$project_to_project_wrapper'
          source "$pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
          open "$TMPDIR/inherited-b.json" | load-env
          source \$apply_a
          cd "$TMPDIR/project-b"
          source \$wrapper
          if \$env.PWD != "$TMPDIR/project-b" { error make { msg: "project-to-project wrapper changed PWD" } }
          if (build) != "built-b" { error make { msg: "project B build command did not replace project A build command" } }
          if (b_only) != "b-only" { error make { msg: "project B unique command did not load" } }
          if ((scope commands | where name == st | is-not-empty)) { error make { msg: "project A command leaked into project B" } }
          if (\$env.PROJECT_MARK? | default "") != "B" { error make { msg: "project B env was not preserved during project-to-project cleanup" } }
          if ((nu-direnv-overlay status | get active | length) != 1) {
            error make { msg: "unexpected active overlay count after project-to-project cleanup" }
          }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/project-to-project-test.nu"

          # Compatibility case: an existing direnv PWD hook has already loaded
          # env, then prompt-sync writes the wrapper. This guards against
          # consuming DIRENV_DIFF from this project.
          external_hook_source=$(
            cd "$TMPDIR/project"
            ${pkgs.nushell}/bin/nu --no-config-file --commands '
              $env.config.hooks.env_change = { PWD: [{|before, after| null }] }
              $env.PATH = ($env.PATH | prepend "${pkgs.direnv}/bin")
              source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
              direnv export json | from json | load-env
              __nu-direnv-overlay prompt-sync
              $nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu"
            '
          )
          if ! grep -q '^source ' "$external_hook_source"; then
            echo "external hook compatibility did not source generated apply" >&2
            cat "$external_hook_source" >&2
            exit 1
          fi
          cat > "$TMPDIR/external-hook-apply-test.nu" <<EOF
          const source_path = '$external_hook_source'
          source \$source_path
          if (build) != "built" { error make { msg: "external hook compatibility did not load build command" } }
          if (st) != "status" { error make { msg: "external hook compatibility did not load st command" } }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/external-hook-apply-test.nu"

          # Build a cleanup wrapper after simulating a directory leave. This is
          # where stale apply paths and active overlays have historically caused
          # command/env resurrection.
          stale_cleanup=$(
            ${pkgs.nushell}/bin/nu --no-config-file --commands '
              source "'"$pkg"'/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
              const apply = "'"$reloaded_apply"'"
              source $apply
              hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
              hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
              $env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST = "generator"
              __nu-direnv-overlay write-source --cleanup-only
              $nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu"
            '
          )
          if ! grep -q 'overlay hide --keep-env .*"nu-direnv-' "$stale_cleanup"; then
            echo "cleanup did not include active nu-direnv overlay" >&2
            cat "$stale_cleanup" >&2
            exit 1
          fi
          if grep -q '^source ' "$stale_cleanup"; then
            echo "cleanup unexpectedly re-sourced an old apply file" >&2
            cat "$stale_cleanup" >&2
            exit 1
          fi
          if ! grep -q 'hide "build"' "$stale_cleanup"; then
            echo "cleanup did not hide build command" >&2
            cat "$stale_cleanup" >&2
            exit 1
          fi
          if ! grep -q 'hide "project_name"' "$stale_cleanup"; then
            echo "cleanup did not hide exported constant" >&2
            cat "$stale_cleanup" >&2
            exit 1
          fi
          if ! grep -q 'hide "nested"' "$stale_cleanup"; then
            echo "cleanup did not hide exported submodule" >&2
            cat "$stale_cleanup" >&2
            exit 1
          fi
          if ! grep -q 'hide "st"' "$stale_cleanup"; then
            echo "cleanup did not hide st command" >&2
            cat "$stale_cleanup" >&2
            exit 1
          fi

          # Source cleanup in a shell with active overlays. It must preserve the
          # current PWD/env, hide leaked exported definitions, and deactivate all
          # project overlays.
          cat > "$TMPDIR/stale-cleanup-test.nu" <<EOF
          const apply = '$reloaded_apply'
          const cleanup = '$stale_cleanup'
          source \$apply
          cd "$TMPDIR"
          \$env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST = "outside"
          source \$cleanup
          if \$env.PWD != "$TMPDIR" {
            error make { msg: "cleanup changed PWD while hiding overlay" }
          }
          if (\$env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST? | default "") != "outside" {
            error make { msg: "cleanup restored environment while hiding overlay" }
          }
          if ((scope commands | where name in [build st] | is-not-empty)) {
            error make { msg: "overlay commands remained visible after cleanup" }
          }
          if ((overlay list | where name =~ '^nu-direnv-' and active == true | is-not-empty)) {
            error make { msg: "nu-direnv overlay remained active after stale cleanup" }
          }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/stale-cleanup-test.nu"

          # Repeated cleanup sources are common because pre_prompt runs on every
          # Enter. They must be idempotent and must not move PWD, even after the
          # user has changed to another unmanaged directory.
          mkdir -p "$TMPDIR/elsewhere/deep"
          cat > "$TMPDIR/repeated-pwd-test.nu" <<EOF
          const apply = '$reloaded_apply'
          const cleanup = '$stale_cleanup'
          source \$apply
          cd "$TMPDIR/elsewhere"
          source \$cleanup
          if \$env.PWD != "$TMPDIR/elsewhere" {
            error make { msg: "first cleanup changed PWD" }
          }
          cd "$TMPDIR/elsewhere/deep"
          source \$cleanup
          if \$env.PWD != "$TMPDIR/elsewhere/deep" {
            error make { msg: "second cleanup changed PWD" }
          }
          source \$cleanup
          if \$env.PWD != "$TMPDIR/elsewhere/deep" {
            error make { msg: "idempotent cleanup changed PWD" }
          }
          EOF
          ${pkgs.nushell}/bin/nu --no-config-file "$TMPDIR/repeated-pwd-test.nu"

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
