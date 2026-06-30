#!/usr/bin/env bash

prepare_repl_fixture() {
  mkdir -p \
    "$TMPDIR/repl-home/.config/direnv" \
    "$TMPDIR/repl-home/.cache/nushell/nu-direnv-overlay" \
    "$TMPDIR/repl-setup/overlay" \
    "$TMPDIR/repl-quitter/overlay" \
    "$TMPDIR/repl-worktree" \
    "$TMPDIR/repl-outside"
  printf 'source %q\n' "$direnv_lib" >"$TMPDIR/repl-home/.config/direnv/direnvrc"
  touch "$TMPDIR/repl-home/home-only.txt"
  touch "$TMPDIR/repl-outside/outside-only.txt"

  cat >"$TMPDIR/repl-setup/.envrc" <<'EOF'
export setup_repo_root="$PWD"
use nu-overlay overlay/task.nu
EOF
  cat >"$TMPDIR/repl-setup/overlay/task.nu" <<'EOF'
export def setup_hi [] { "hi" }
EOF

  cat >"$TMPDIR/repl-quitter/.envrc" <<'EOF'
export quitter_repo_root="$PWD"
use nu-overlay overlay/task.nu
EOF
  cat >"$TMPDIR/repl-quitter/overlay/task.nu" <<'EOF'
export def quitter_hi [] { "quit" }
EOF

  (
    cd "$TMPDIR/repl-setup"
    HOME="$TMPDIR/repl-home" \
      XDG_CONFIG_HOME="$TMPDIR/repl-home/.config" \
      XDG_DATA_HOME="$TMPDIR/repl-home/.local/share" \
      XDG_CACHE_HOME="$TMPDIR/repl-home/.cache" \
      "$DIRENV" allow . >/dev/null
  )
  (
    cd "$TMPDIR/repl-quitter"
    HOME="$TMPDIR/repl-home" \
      XDG_CONFIG_HOME="$TMPDIR/repl-home/.config" \
      XDG_DATA_HOME="$TMPDIR/repl-home/.local/share" \
      XDG_CACHE_HOME="$TMPDIR/repl-home/.cache" \
      "$DIRENV" allow . >/dev/null
  )
}

write_repl_autoload() {
  repl_wrapper="$TMPDIR/repl-home/.cache/nushell/nu-direnv-overlay/wrapper.nu"
  : >"$repl_wrapper"
  repl_autoload="$TMPDIR/repl-autoload.nu"
  awk -v wrapper="$repl_wrapper" '
    /^const overlay_source = / { print "const overlay_source = \"" wrapper "\""; next }
    /if \$nu.is-interactive/ { print "if true {"; next }
    { print }
  ' "$autoload" >"$repl_autoload"
}

repl_env_source() {
  printf '%s' '$env.config = { hooks: { pre_prompt: [] pre_execution: [] env_change: { PWD: [] } } }; $env.HOME = "'"$TMPDIR/repl-home"'"; $env.XDG_CONFIG_HOME = "'"$TMPDIR/repl-home/.config"'"; $env.XDG_DATA_HOME = "'"$TMPDIR/repl-home/.local/share"'"; $env.XDG_CACHE_HOME = "'"$TMPDIR/repl-home/.cache"'"; $env.PATH = ("'"$PATH"'" | split row (char esep) | prepend "'"$direnv_bin_dir"'")'
}

run_repl_state_regressions() {
  # nu_repl runs Nushell's interactive hook machinery between input lines. That
  # covers command resolution and prompt-time shell state without a terminal.
  local repl_env
  repl_env=$(repl_env_source)

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
  # overlays. The prompt must see the unmanaged directory and no project
  # command; active overlay frames may be deferred because prompt-time
  # `overlay hide` can make Nushell's file completer use a stale cwd.
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
    if ($state.apply != null and $state.apply != "") {
      error make { msg: "prompt state kept stale apply path in unmanaged directory" }
    }
    if $state.setup_visible {
      error make { msg: "prompt state kept setup command visible in unmanaged directory" }
    }
    if "outside-only.txt" not-in $state.files {
      error make { msg: "prompt-time file view was not based on unmanaged directory" }
    }
  '

  # Regression for repeated project/unmanaged/project transitions. Active
  # overlay frames are intentionally deferred, but exported commands must not
  # stay visible in unrelated directories or projects after several prompt
  # cycles.
  rm -f "$TMPDIR/repl-navigation-states.nuon"
  "$NU" --testbin=nu_repl \
    "$repl_env; "'source "'"$repl_autoload"'"; $env.__TEST_NAV_STATES = []; $env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | append {|| let pwd = (pwd); if ($pwd | str starts-with "'"$TMPDIR"'") { let row = { pwd: $pwd, setup_visible: (scope commands | where name == setup_hi | is-not-empty), quitter_visible: (scope commands | where name == quitter_hi | is-not-empty), apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default ""), active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default ""), exports: ($env.NU_DIRENV_OVERLAY_EXPORTS? | default ""), loaded: ($env.NU_DIRENV_OVERLAY_APPLY_LOADED? | default ""), frames: (overlay list | where name =~ "^nu-direnv-" and active == true | get name) }; $env.__TEST_NAV_STATES = ($env.__TEST_NAV_STATES | append $row); $env.__TEST_NAV_STATES | to nuon | save --force "'"$TMPDIR/repl-navigation-states.nuon"'" } })' \
    'cd "'"$TMPDIR/repl-setup"'"' \
    'cd "'"$TMPDIR/repl-home"'"' \
    'cd "'"$TMPDIR/repl-quitter"'"' \
    'cd "'"$TMPDIR/repl-outside"'"' \
    'cd "'"$TMPDIR/repl-setup"'"' \
    'cd "'"$TMPDIR/repl-worktree"'"' \
    'cd "'"$TMPDIR/repl-quitter"'"' \
    'cd "'"$TMPDIR/repl-home"'"' \
    '"done"'

  run_nu --commands '
    let states = (open "'"$TMPDIR/repl-navigation-states.nuon"'")
    for state in $states {
      if $state.pwd == "'"$TMPDIR/repl-setup"'" {
        if not $state.setup_visible {
          error make { msg: "setup command was not visible inside setup project" }
        }
        if $state.quitter_visible {
          error make { msg: "quitter command leaked into setup project" }
        }
      } else if $state.pwd == "'"$TMPDIR/repl-quitter"'" {
        if not $state.quitter_visible {
          error make { msg: "quitter command was not visible inside quitter project" }
        }
        if $state.setup_visible {
          error make { msg: "setup command leaked into quitter project" }
        }
      } else if $state.pwd in ["'"$TMPDIR/repl-home"'" "'"$TMPDIR/repl-outside"'" "'"$TMPDIR/repl-worktree"'"] {
        if $state.setup_visible or $state.quitter_visible {
          error make { msg: $"project command leaked into unmanaged directory: ($state | to nuon)" }
        }
        if $state.apply != "" {
          error make { msg: $"unmanaged directory kept stale apply path: ($state | to nuon)" }
        }
      }
    }
  '
}

write_repl_pty_bootstrap() {
  local bootstrap=$1

  cat >"$bootstrap" <<EOF
\$env.PATH = (\$env.PATH | prepend "$direnv_bin_dir")

def --env __test-direnv-load [] {
  let exported = (direnv export json | from json --strict | default {})
  for row in (\$exported | transpose name value) {
    if \$row.value == null {
      hide-env \$row.name --ignore-errors
    } else {
      load-env { \$row.name: \$row.value }
    }
  }
}

\$env.config.hooks.pre_prompt = (\$env.config.hooks.pre_prompt | append "__test-direnv-load")
source "$repl_autoload"
EOF
}

run_repl_pty_completion_scenario() {
  # This uses a real PTY because Nushell path completion is driven by Reedline
  # Tab handling, not by ordinary command evaluation. Each scenario provides the
  # command path to a prompt and one Tab completion assertion.
  : "${EXPECT:?}"

  local name=$1
  local completion_input=$2
  local expected_pattern=$3
  shift 3

  local expect_script="$TMPDIR/repl-pty-$name.expect"
  local bootstrap="$TMPDIR/repl-pty-$name-bootstrap.nu"
  local transcript="$TMPDIR/repl-pty-$name.log"
  local commands_file="$TMPDIR/repl-pty-$name-commands.tcl"

  write_repl_pty_bootstrap "$bootstrap"

  : >"$commands_file"
  local line
  for line in "$@"; do
    printf 'run_line {%s}\n' "$line" >>"$commands_file"
  done

  cat >"$expect_script" <<EOF
set timeout 20
log_file -noappend "$transcript"
cd "$TMPDIR/repl-home"
set bootstrap {source "$bootstrap"}

proc fail {message} {
  puts stderr \$message
  exit 1
}

proc wait_prompt {context} {
  expect {
    -exact "\033]133;B" {}
    timeout { fail "timed out waiting for prompt: \$context" }
    eof { fail "nushell exited while waiting for prompt: \$context" }
  }
}

proc run_line {line} {
  send -- "\$line\r"
  expect {
    -exact "\033]133;D;0" {}
    timeout { fail "timed out waiting for command completion: \$line" }
    eof { fail "nushell exited while running: \$line" }
  }
  wait_prompt "after: \$line"
}

spawn env TERM=xterm-256color HOME=$TMPDIR/repl-home XDG_CONFIG_HOME=$TMPDIR/repl-home/.config XDG_DATA_HOME=$TMPDIR/repl-home/.local/share XDG_CACHE_HOME=$TMPDIR/repl-home/.cache PATH=$direnv_bin_dir:$PATH "$NU" --execute \$bootstrap --no-history --no-config-file

expect_before {
  -exact "\033\[6n" {
    send -- "\\033\\[24;80R"
    exp_continue
  }
}

expect {
  -exact "\033]133;B" {}
  timeout { fail "timed out waiting for initial prompt" }
  eof { fail "nushell exited before initial prompt" }
}

source "$commands_file"

send -- "$completion_input\t"
expect {
  -re "$expected_pattern" {}
  -re "NO RECORDS FOUND" { fail "path completion did not see the unmanaged prompt cwd" }
  -re "home-only\\.txt" { fail "path completion used stale home cwd" }
  timeout { fail "timed out waiting for path completion result" }
  eof { fail "nushell exited while completing path" }
}

send -- "\\025exit\r"
expect {
  eof {}
  timeout { fail "timed out waiting for nushell to exit" }
}
EOF

  if ! "$EXPECT" "$expect_script"; then
    cat "$transcript" >&2 || true
    exit 1
  fi
}

run_repl_path_completion_regression() {
  run_repl_pty_completion_scenario \
    unmanaged-path-completion \
    "ls outside" \
    "outside-only\\.txt" \
    "cd \"$TMPDIR/repl-setup\"" \
    "cd \"$TMPDIR/repl-home\"" \
    "cd \"$TMPDIR/repl-outside\""
}

run_repl_command_completion_regression() {
  run_repl_pty_completion_scenario \
    project-command-completion \
    "setup_" \
    "setup_hi" \
    "cd \"$TMPDIR/repl-setup\""
}

run_repl_regressions() {
  prepare_repl_fixture
  write_repl_autoload
  run_repl_state_regressions
  run_repl_command_completion_regression
  run_repl_path_completion_regression
}
