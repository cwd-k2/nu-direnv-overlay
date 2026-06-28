#!/usr/bin/env bash
set -eu

: "${PKG:?}"
: "${NU:?}"
: "${DIRENV:?}"
: "${TMPDIR:?}"

autoload="$PKG/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
direnv_lib="$PKG/share/direnv/lib/nu-overlay.sh"
direnv_bin_dir=$(dirname "$DIRENV")

run_nu() {
  "$NU" --no-config-file "$@"
}

wrapper_path='
$nu.cache-dir | path join "nu-direnv-overlay" $"($nu.pid).nu"
'

assert_project_commands='
if (build) != "built" { error make { msg: "build command did not load" } }
if (st) != "status" { error make { msg: "st command did not load" } }
'

export HOME="$TMPDIR/home"
export XDG_CONFIG_HOME="$TMPDIR/config"
export XDG_DATA_HOME="$TMPDIR/data"
export XDG_CACHE_HOME="$TMPDIR/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/direnv" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

test -x "$PKG/bin/nu-direnv-overlay"
test -f "$direnv_lib"
test -f "$autoload"

# Ensure the direnv-side library defines the .envrc API.
"$DIRENV" stdlib >"$TMPDIR/stdlib.sh"
. "$direnv_lib"
type use_nu-overlay >/dev/null

# Ensure the Nushell-side autoload file can be sourced in a clean shell.
run_nu --commands 'source "'"$autoload"'"; nu-direnv-overlay status | ignore'

# Prompt hook installation must be idempotent. The sync and source hooks are
# installed adjacent to each other so the source hook sees freshly written
# wrapper contents.
run_nu --commands '
  source "'"$autoload"'"
  $env.config.hooks.env_change = { PWD: [{|before, after| "existing" }] }
  let wrapper = ($nu.cache-dir | path join "nu-direnv-overlay" $"($nu.pid).nu")
  let legacy_wrapper = ($nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu")
  let sq = (char -i 39)
  mkdir ($wrapper | path dirname)
  "error make { msg: \"stale wrapper was sourced\" }" | save --force $wrapper
  $env.config.hooks.pre_prompt = [
    "existing hook"
    $"__nu-direnv-overlay prompt-sync; source ($sq)($legacy_wrapper)($sq)"
    "__nu-direnv-overlay prompt-sync"
    $"source ($sq)($legacy_wrapper)($sq)"
  ]
  __nu-direnv-overlay install-prompt-hooks
  __nu-direnv-overlay install-prompt-hooks
  let hooks = ($env.config.hooks.pre_prompt | last 2)
  if "existing hook" not-in $env.config.hooks.pre_prompt {
    error make { msg: "unrelated prompt hook was removed" }
  }
  if ($env.config.hooks.pre_prompt | where {|hook| $hook =~ "nu-direnv-overlay-"} | is-not-empty) {
    error make { msg: "legacy tmp prompt hook was not removed" }
  }
  if $hooks.0 != "__nu-direnv-overlay prompt-sync" {
    error make { msg: "prompt sync hook was not installed before source hook" }
  }
  if (($hooks.1 | str starts-with "source ") != true) {
    error make { msg: "prompt source hook was not installed after sync hook" }
  }
  if (($env.config.hooks.pre_prompt | where $it == $hooks.0 | length) != 1) {
    error make { msg: "prompt hook installation was not idempotent" }
  }
  if (($env.config.hooks.pre_prompt | where $it == $hooks.1 | length) != 1) {
    error make { msg: "prompt source hook installation was not idempotent" }
  }
  if not ($wrapper | path exists) {
    error make { msg: "prompt source wrapper was not created before hook installation" }
  }
  if ((open $wrapper) != "") {
    error make { msg: "stale prompt source wrapper was not reset on install" }
  }
'

# Synthetic projects:
# - project has two overlay files, so cleanup must handle multiple internal
#   overlay names and exported definitions.
# - project-b overlaps `build`, so project-to-project movement must replace
#   commands without rolling direnv's new env back.
printf 'source %q\n' "$direnv_lib" >"$XDG_CONFIG_HOME/direnv/direnvrc"
mkdir -p "$TMPDIR/project/overlay"
cat >"$TMPDIR/project/.envrc" <<'EOF'
export PROJECT_ROOT="$PWD"
use nu-overlay overlay/task.nu
use nu-overlay overlay/git.nu
EOF
cat >"$TMPDIR/project/overlay/task.nu" <<'EOF'
export const project_name = "project"
export module nested { export def hi [] { "hi" } }
export def build [] { "built" }
export def --env "jump root" [] { cd $env.PROJECT_ROOT }
EOF
cat >"$TMPDIR/project/overlay/git.nu" <<'EOF'
export def st [] { "status" }
EOF
mkdir -p "$TMPDIR/project-b/overlay"
cat >"$TMPDIR/project-b/.envrc" <<'EOF'
export PROJECT_MARK=B
use nu-overlay overlay/task.nu
EOF
cat >"$TMPDIR/project-b/overlay/task.nu" <<'EOF'
export def build [] { "built-b" }
export def b_only [] { "b-only" }
EOF

(
  cd "$TMPDIR/project"
  "$DIRENV" allow . >/dev/null
)
(
  cd "$TMPDIR/project-b"
  "$DIRENV" allow . >/dev/null
)

# direnv evaluation should produce an apply file path for the parent Nushell
# hook to consume.
apply=$(
  cd "$TMPDIR/project"
  run_nu --commands "$DIRENV export json | from json | get DIRENV_NU_OVERLAY_APPLY"
)
test -f "$apply"

# The raw apply file must be valid Nushell and expose project commands.
cat >"$TMPDIR/apply-test.nu" <<EOF
const apply = '$apply'
source \$apply
$assert_project_commands
if not ((overlay list | where name =~ '^nu-direnv-' | is-not-empty)) {
  error make { msg: "nu-direnv overlay names were not created" }
}
EOF
run_nu "$TMPDIR/apply-test.nu"

# Simulate the normal direnv hook loading env before nu-direnv-overlay syncs
# overlays from the inherited DIRENV_NU_OVERLAY_APPLY value.
(
  cd "$TMPDIR/project"
  "$DIRENV" export json >"$TMPDIR/inherited.json"
  "$DIRENV" export json >"$TMPDIR/inherited-again.json"
)
(
  cd "$TMPDIR/project-b"
  "$DIRENV" export json >"$TMPDIR/inherited-b.json"
)

cat >"$TMPDIR/inherited-reload.nu" <<EOF
open "$TMPDIR/inherited.json" | load-env
\$env.PATH = (\$env.PATH | prepend "$direnv_bin_dir")
source "$autoload"
__nu-direnv-overlay sync-overlays
nu-direnv-overlay status | get apply
EOF
hook_apply=$(
  cd "$TMPDIR/project"
  run_nu "$TMPDIR/inherited-reload.nu"
)
test -f "$hook_apply"

# The wrapper produced from inherited direnv state should load the same commands
# as the raw apply file.
cat >"$TMPDIR/hook-apply-test.nu" <<EOF
const apply = '$hook_apply'
source \$apply
$assert_project_commands
EOF
run_nu "$TMPDIR/hook-apply-test.nu"

# Manual reload is overlay-only: it should resync from current env without
# calling direnv itself.
cat >"$TMPDIR/inherited-force-reload.nu" <<EOF
open "$TMPDIR/inherited.json" | load-env
\$env.PATH = (\$env.PATH | prepend "$direnv_bin_dir")
source "$autoload"
nu-direnv-overlay reload
nu-direnv-overlay status | get apply
EOF
reloaded_apply=$(
  cd "$TMPDIR/project"
  run_nu "$TMPDIR/inherited-force-reload.nu"
)
test -f "$reloaded_apply"

cat >"$TMPDIR/reloaded-apply-test.nu" <<EOF
const apply = '$reloaded_apply'
source \$apply
$assert_project_commands
EOF
run_nu "$TMPDIR/reloaded-apply-test.nu"

# Repeated prompt syncs inside the same project must be a no-op after the apply
# file is already active. Hiding and re-sourcing the same internal overlay can
# leave Nushell reporting the module as active while exported commands are
# hidden and unusable.
same_project_wrapper=$(
  run_nu --commands '
    source "'"$autoload"'"
    open "'"$TMPDIR/inherited.json"'" | load-env
    const apply = "'"$reloaded_apply"'"
    source $apply
    __nu-direnv-overlay write-source
    '"$wrapper_path"'
  '
)
test -f "$same_project_wrapper"
test ! -s "$same_project_wrapper"
cat >"$TMPDIR/same-project-wrapper-test.nu" <<EOF
const apply = '$reloaded_apply'
const wrapper = '$same_project_wrapper'
source "$autoload"
open "$TMPDIR/inherited.json" | load-env
source \$apply
source \$wrapper
$assert_project_commands
if ((nu-direnv-overlay status | get active | length) != 2) {
  error make { msg: "unexpected active overlay count after same-project no-op" }
}
EOF
run_nu "$TMPDIR/same-project-wrapper-test.nu"

# A setup-style command may `cd` to a repository root before returning to the
# prompt. The following prompt sync must not restore the directory that was
# current when the overlay originally loaded.
cat >"$TMPDIR/command-cd-prompt-test.nu" <<EOF
const apply = '$reloaded_apply'
source "$autoload"
open "$TMPDIR/inherited.json" | load-env
source \$apply
cd "$TMPDIR"
jump root
if \$env.PWD != "$TMPDIR/project" {
  error make { msg: "overlay command did not cd to project root" }
}
__nu-direnv-overlay write-source
let wrapper = (\$nu.cache-dir | path join "nu-direnv-overlay" $"(\$nu.pid).nu")
if ((ls \$wrapper | get size.0 | into int) != 0) {
  error make { msg: "prompt sync after command cd was not a no-op" }
}
if \$env.PWD != "$TMPDIR/project" {
  error make { msg: "prompt sync after command cd changed PWD" }
}
EOF
run_nu "$TMPDIR/command-cd-prompt-test.nu"

# Some direnv hooks re-evaluate on prompt, so the same project can receive a new
# apply file path after a command has changed PWD. That must not roll the command
# driven directory change back to the overlay activation directory.
changed_apply_after_cd_wrapper=$(
  run_nu --commands '
    source "'"$autoload"'"
    open "'"$TMPDIR/inherited.json"'" | load-env
    const apply = "'"$reloaded_apply"'"
    source $apply
    cd "'"$TMPDIR"'"
    jump root
    open "'"$TMPDIR/inherited-again.json"'" | load-env
    __nu-direnv-overlay write-source
    '"$wrapper_path"'
  '
)
cat >"$TMPDIR/changed-apply-after-cd-test.nu" <<EOF
const apply = '$reloaded_apply'
const wrapper = '$changed_apply_after_cd_wrapper'
source "$autoload"
open "$TMPDIR/inherited.json" | load-env
source \$apply
cd "$TMPDIR"
jump root
open "$TMPDIR/inherited-again.json" | load-env
source \$wrapper
if \$env.PWD != "$TMPDIR/project" {
  error make { msg: "changed apply after command cd changed PWD" }
}
$assert_project_commands
EOF
run_nu "$TMPDIR/changed-apply-after-cd-test.nu"

# Direct project-to-project movement is different from leaving to an unmanaged
# directory: cleanup for project A runs while direnv has already loaded project
# B's environment and apply path. A cleanup must not roll B's env back, and B's
# apply must replace overlapping command names such as `build`.
project_to_project_wrapper=$(
  run_nu --commands '
    source "'"$autoload"'"
    const apply_a = "'"$reloaded_apply"'"
    open "'"$TMPDIR/inherited-b.json"'" | load-env
    source $apply_a
    __nu-direnv-overlay write-source
    '"$wrapper_path"'
  '
)
cat >"$TMPDIR/project-to-project-test.nu" <<EOF
const apply_a = '$reloaded_apply'
const wrapper = '$project_to_project_wrapper'
source "$autoload"
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
run_nu "$TMPDIR/project-to-project-test.nu"

# Compatibility case: an existing direnv PWD hook has already loaded env, then
# prompt-sync writes the wrapper. This guards against consuming DIRENV_DIFF from
# this project.
external_hook_source=$(
  cd "$TMPDIR/project"
  run_nu --commands '
    $env.config.hooks.env_change = { PWD: [{|before, after| null }] }
    $env.PATH = ($env.PATH | prepend "'"$direnv_bin_dir"'")
    source "'"$autoload"'"
    direnv export json | from json | load-env
    __nu-direnv-overlay prompt-sync
    '"$wrapper_path"'
  '
)
if ! grep -q '^source ' "$external_hook_source"; then
  echo "external hook compatibility did not source generated apply" >&2
  cat "$external_hook_source" >&2
  exit 1
fi
cat >"$TMPDIR/external-hook-apply-test.nu" <<EOF
const source_path = '$external_hook_source'
source \$source_path
$assert_project_commands
EOF
run_nu "$TMPDIR/external-hook-apply-test.nu"

# Build a cleanup wrapper after simulating a directory leave. This is where
# stale apply paths and active overlays have historically caused command/env
# resurrection.
stale_cleanup=$(
  run_nu --commands '
    source "'"$autoload"'"
    const apply = "'"$reloaded_apply"'"
    source $apply
    hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
    hide-env NU_DIRENV_OVERLAY_EXPORTS --ignore-errors
    hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
    hide-env PROJECT_ROOT --ignore-errors
    $env.PROJECT_MARK = "outside"
    $env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST = "outside"
    $env.PROMPT_COMMAND = {|| "prompt" }
    __nu-direnv-overlay write-source --cleanup-only
    '"$wrapper_path"'
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
for exported in build project_name nested st; do
  if ! grep -q "hide \"$exported\"" "$stale_cleanup"; then
    echo "cleanup did not hide $exported" >&2
    cat "$stale_cleanup" >&2
    exit 1
  fi
done

# Source cleanup in a shell with active overlays. It must preserve the current
# PWD/env, hide leaked exported definitions, and deactivate all project overlays.
cat >"$TMPDIR/stale-cleanup-test.nu" <<EOF
const apply = '$reloaded_apply'
const cleanup = '$stale_cleanup'
source \$apply
cd "$TMPDIR"
hide-env PROJECT_ROOT --ignore-errors
\$env.PROJECT_MARK = "outside"
\$env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST = "outside"
\$env.PROMPT_COMMAND = {|| "prompt" }
source \$cleanup
if \$env.PWD != "$TMPDIR" {
  error make { msg: "cleanup changed PWD while hiding overlay" }
}
if (\$env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST? | default "") != "outside" {
  error make { msg: "cleanup restored environment while hiding overlay" }
}
if (\$env.PROJECT_ROOT? | default "") != "" {
  error make { msg: "cleanup resurrected unloaded direnv environment" }
}
if (\$env.PROJECT_MARK? | default "") != "outside" {
  error make { msg: "cleanup did not preserve same-named current env value" }
}
if (do \$env.PROMPT_COMMAND) != "prompt" {
  error make { msg: "cleanup removed prompt closure" }
}
if ((scope commands | where name in [build st] | is-not-empty)) {
  error make { msg: "overlay commands remained visible after cleanup" }
}
if ((overlay list | where name =~ '^nu-direnv-' and active == true | is-not-empty)) {
  error make { msg: "nu-direnv overlay remained active after stale cleanup" }
}
EOF
run_nu "$TMPDIR/stale-cleanup-test.nu"

# Repeated cleanup sources are common because pre_prompt runs on every Enter.
# They must be idempotent and must not move PWD, even after the user has changed
# to another unmanaged directory.
mkdir -p "$TMPDIR/elsewhere/deep"
cat >"$TMPDIR/repeated-pwd-test.nu" <<EOF
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
run_nu "$TMPDIR/repeated-pwd-test.nu"

# Full navigation regression for setup -> project-b -> unmanaged -> setup.
# The setup-like env var must be absent outside setup-like project state and
# restored when entering it again.
setup_roundtrip_cleanup=$(
  run_nu --commands '
    source "'"$autoload"'"
    const apply = "'"$reloaded_apply"'"
    source $apply
    hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
    hide-env NU_DIRENV_OVERLAY_EXPORTS --ignore-errors
    hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
    hide-env PROJECT_ROOT --ignore-errors
    __nu-direnv-overlay write-source --cleanup-only
    '"$wrapper_path"'
  '
)
setup_roundtrip_apply=$(
  run_nu --commands '
    source "'"$autoload"'"
    open "'"$TMPDIR/inherited.json"'" | load-env
    __nu-direnv-overlay write-source
    '"$wrapper_path"'
  '
)
cat >"$TMPDIR/setup-roundtrip-test.nu" <<EOF
const apply_a = '$reloaded_apply'
const cleanup = '$setup_roundtrip_cleanup'
const apply_again = '$setup_roundtrip_apply'
const project_to_project = '$project_to_project_wrapper'
source "$autoload"
open "$TMPDIR/inherited.json" | load-env
source \$apply_a
if (\$env.PROJECT_ROOT? | default "") != "$TMPDIR/project" {
  error make { msg: "setup-like env did not load initially" }
}
open "$TMPDIR/inherited-b.json" | load-env
source \$project_to_project
if (\$env.PROJECT_ROOT? | default "") != "" {
  error make { msg: "setup-like env leaked into project-b" }
}
hide-env PROJECT_MARK --ignore-errors
hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
source \$cleanup
if (\$env.PROJECT_ROOT? | default "") != "" {
  error make { msg: "setup-like env resurrected in unmanaged directory" }
}
open "$TMPDIR/inherited.json" | load-env
source \$apply_again
if (\$env.PROJECT_ROOT? | default "") != "$TMPDIR/project" {
  error make { msg: "setup-like env did not restore after returning" }
}
EOF
run_nu "$TMPDIR/setup-roundtrip-test.nu"
