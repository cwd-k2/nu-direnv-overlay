#!/usr/bin/env bash

run_repl_regressions() {
  # These tests use nu_repl because it runs Nushell's interactive hook
  # machinery between input lines. That is the only stable non-visual way to
  # cover command resolution and prompt-time state.
  mkdir -p \
    "$TMPDIR/repl-home/.config/direnv" \
    "$TMPDIR/repl-home/.cache/nushell/nu-direnv-overlay" \
    "$TMPDIR/repl-setup/overlay" \
    "$TMPDIR/repl-outside"
  printf 'source %q\n' "$direnv_lib" >"$TMPDIR/repl-home/.config/direnv/direnvrc"

  cat >"$TMPDIR/repl-setup/.envrc" <<'EOF'
export setup_repo_root="$PWD"
use nu-overlay overlay/task.nu
EOF
  cat >"$TMPDIR/repl-setup/overlay/task.nu" <<'EOF'
export def setup_hi [] { "hi" }
EOF

  (
    cd "$TMPDIR/repl-setup"
    HOME="$TMPDIR/repl-home" \
      XDG_CONFIG_HOME="$TMPDIR/repl-home/.config" \
      XDG_DATA_HOME="$TMPDIR/repl-home/.local/share" \
      XDG_CACHE_HOME="$TMPDIR/repl-home/.cache" \
      "$DIRENV" allow . >/dev/null
  )

  repl_wrapper="$TMPDIR/repl-home/.cache/nushell/nu-direnv-overlay/wrapper.nu"
  : >"$repl_wrapper"
  repl_autoload="$TMPDIR/repl-autoload.nu"
  awk -v wrapper="$repl_wrapper" '
    /^const overlay_source = / { print "const overlay_source = \"" wrapper "\""; next }
    /if \$nu.is-interactive/ { print "if true {"; next }
    { print }
  ' "$autoload" >"$repl_autoload"

  local repl_env
  repl_env='$env.config = { hooks: { pre_prompt: [] pre_execution: [] env_change: { PWD: [] } } }; $env.HOME = "'"$TMPDIR/repl-home"'"; $env.XDG_CONFIG_HOME = "'"$TMPDIR/repl-home/.config"'"; $env.XDG_DATA_HOME = "'"$TMPDIR/repl-home/.local/share"'"; $env.XDG_CACHE_HOME = "'"$TMPDIR/repl-home/.cache"'"; $env.PATH = ("'"$PATH"'" | split row (char esep) | prepend "'"$direnv_bin_dir"'")'

  # Command-cycle regression for setup -> unmanaged -> setup. The split
  # pre_execution hooks must refresh and source the wrapper before the user's
  # first command after re-enter resolves.
  "$NU" --testbin=nu_repl \
    "$repl_env; "'$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | append {|| direnv export json | from json --strict | default {} | items {|key, value| let value = do ({"PATH": {from_string: {|s| $s | split row (char esep) | path expand --no-symlink } to_string: {|v| $v | path expand --no-symlink | str join (char esep) }}} | merge ($env.ENV_CONVERSIONS? | default {}) | get ([[value, optional, insensitive]; [$key, true, true] [from_string, true, false]] | into cell-path) | if ($in | is-empty) { {|x| $x} } else { $in }) $value; return [$key $value] } | into record | load-env }); source "'"$repl_autoload"'"' \
    'cd "'"$TMPDIR/repl-setup"'"' \
    'cd "'"$TMPDIR/repl-outside"'"' \
    'cd "'"$TMPDIR/repl-setup"'"' \
    'let apply = ($env.DIRENV_NU_OVERLAY_APPLY? | default ""); let root = ($env.setup_repo_root? | default ""); if $apply == "" { error make { msg: "missing apply before first re-enter command" } }; if $root != "'"$TMPDIR/repl-setup"'" { error make { msg: "missing setup root before first re-enter command" } }; setup_hi | save --force "'"$TMPDIR/repl-direct-command.txt"'"'
  grep -Fx hi "$TMPDIR/repl-direct-command.txt" >/dev/null

  # Prompt-time regression for setup -> unmanaged. Path completion reads state
  # at the prompt, before any next command pre_execution hook can clean up stale
  # overlays. The pre_prompt hook must therefore source cleanup before the next
  # prompt is shown, so the prompt sees the unmanaged directory and no project
  # command.
  touch "$TMPDIR/repl-outside/outside-only.txt"
  rm -f "$TMPDIR/repl-prompt-state.nuon"
  "$NU" --testbin=nu_repl \
    "$repl_env; "'source "'"$repl_autoload"'"; $env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | append {|| if (pwd) == "'"$TMPDIR/repl-outside"'" { { pwd: (pwd), env_pwd: $env.PWD, apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null), active: (overlay list | where name =~ "^nu-direnv-" and active == true | get name), setup_visible: (scope commands | where name == setup_hi | is-not-empty), files: (ls | get name | path basename) } | to nuon | save --force "'"$TMPDIR/repl-prompt-state.nuon"'" } })' \
    'cd "'"$TMPDIR/repl-setup"'"' \
    'cd "'"$TMPDIR/repl-outside"'"' \
    '"done"'

  run_nu --commands '
    let state = (open "'"$TMPDIR/repl-prompt-state.nuon"'")
    if $state.pwd != "'"$TMPDIR/repl-outside"'" {
      error make { msg: "prompt state did not record unmanaged PWD" }
    }
    if $state.env_pwd != "'"$TMPDIR/repl-outside"'" {
      error make { msg: "prompt state env PWD was not unmanaged PWD" }
    }
    if $state.apply != null {
      error make { msg: "prompt state kept stale apply path in unmanaged directory" }
    }
    if ($state.active | is-not-empty) {
      error make { msg: "prompt state kept active nu-direnv overlay in unmanaged directory" }
    }
    if $state.setup_visible {
      error make { msg: "prompt state kept setup command visible in unmanaged directory" }
    }
    if "outside-only.txt" not-in $state.files {
      error make { msg: "prompt-time file view was not based on unmanaged directory" }
    }
  '
}
