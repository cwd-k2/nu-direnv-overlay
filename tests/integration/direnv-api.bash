# shellcheck shell=bash

assert_direnv_export_has_no_apply() {
  local project_dir=$1
  local message=$2
  local out="$project_dir/export.json"

  (
    cd "$project_dir"
    "$DIRENV" export json >"$out" 2>/dev/null || true
  )

  if grep -q 'DIRENV_NU_OVERLAY_APPLY' "$out"; then
    echo "$message: failed export leaked DIRENV_NU_OVERLAY_APPLY" >&2
    cat "$out" >&2
    exit 1
  fi
}

assert_direnv_generated_apply_shape() {
  local project_dir=$1
  local apply

  apply=$(apply_path_for "$project_dir")
  test -f "$apply"
  test "$(grep -c '^overlay use --reload ' "$apply")" -eq 2
  test "$(grep -cF ' as "nu-direnv-' "$apply")" -eq 2
  assert_file_contains "$apply" '# task' "generated apply did not keep logical task comment"
  assert_file_contains "$apply" '# git' "generated apply did not keep logical git comment"
  assert_file_contains "$apply" 'NU_DIRENV_OVERLAY_ACTIVE' "generated apply did not track active overlays"
  assert_file_contains "$apply" 'NU_DIRENV_OVERLAY_EXPORTS' "generated apply did not track exported definitions"
}

assert_direnv_duplicate_overlay_is_idempotent() {
  local project_dir="$TMPDIR/duplicate-overlay"
  local apply

  mkdir -p "$project_dir/overlay"
  cat >"$project_dir/.envrc" <<'EOF'
use nu-overlay overlay/task.nu
use nu-overlay overlay/task.nu
EOF
  cat >"$project_dir/overlay/task.nu" <<'EOF'
export def duplicate_hi [] { "duplicate-ok" }
EOF
  allow_fixture "$project_dir"

  apply=$(apply_path_for "$project_dir")
  test -f "$apply"
  test "$(grep -c '^overlay use --reload ' "$apply")" -eq 1
}

assert_direnv_duplicate_overlay_canonical_paths_are_idempotent() {
  local project_dir="$TMPDIR/duplicate-canonical-overlay"
  local apply

  mkdir -p "$project_dir/overlay"
  cat >"$project_dir/.envrc" <<'EOF'
use nu-overlay overlay/task.nu
use nu-overlay ./overlay/../overlay/task.nu
EOF
  cat >"$project_dir/overlay/task.nu" <<'EOF'
export def duplicate_canonical_hi [] { "duplicate-canonical-ok" }
EOF
  allow_fixture "$project_dir"

  apply=$(apply_path_for "$project_dir")
  test -f "$apply"
  test "$(grep -c '^overlay use --reload ' "$apply")" -eq 1
  run_nu --commands 'source '"$(nu_quote "$apply")"'; if (duplicate_canonical_hi) != "duplicate-canonical-ok" { error make { msg: "canonical duplicate overlay did not load" } }; if (($env.NU_DIRENV_OVERLAY_ACTIVE | split row ";") | length) != 1 { error make { msg: "canonical duplicate overlay tracked more than once" } }'
}

assert_direnv_quoted_overlay_paths_source_successfully() {
  local project_dir="$TMPDIR/quoted-overlay-path"
  local overlay_dir='overlay "dir'
  local overlay_file='task \quoted".nu'
  local apply

  mkdir -p "$project_dir/$overlay_dir"
  cat >"$project_dir/.envrc" <<'EOF'
use nu-overlay 'overlay "dir/task \quoted".nu'
EOF
  cat >"$project_dir/$overlay_dir/$overlay_file" <<'EOF'
export def quoted_overlay_path_hi [] { "quoted-path-ok" }
EOF
  allow_fixture "$project_dir"

  apply=$(apply_path_for "$project_dir")
  test -f "$apply"
  run_nu --commands 'source '"$(nu_quote "$apply")"'; if (quoted_overlay_path_hi) != "quoted-path-ok" { error make { msg: "quoted overlay path did not source" } }'
}

json_string_field() {
  local field=$1
  local file=$2

  run_nu --commands 'open '"$(nu_quote "$file")"' | get '"$field"
}

assert_direnv_overlay_module_change_rebuilds_apply() {
  local project_dir="$TMPDIR/reload-watched-overlay"
  local first_json="$TMPDIR/reload-watched-overlay-first.json"
  local second_json="$TMPDIR/reload-watched-overlay-second.json"
  local first_apply second_apply
  local old_diff old_dir old_file old_watches

  mkdir -p "$project_dir/overlay"
  cat >"$project_dir/.envrc" <<'EOF'
use nu-overlay overlay/task.nu
EOF
  cat >"$project_dir/overlay/task.nu" <<'EOF'
export def reload_watched [] { "one" }
EOF
  allow_fixture "$project_dir"

  direnv_json_for "$project_dir" "$first_json"
  first_apply=$(json_string_field DIRENV_NU_OVERLAY_APPLY "$first_json")
  old_diff=$(json_string_field DIRENV_DIFF "$first_json")
  old_dir=$(json_string_field DIRENV_DIR "$first_json")
  old_file=$(json_string_field DIRENV_FILE "$first_json")
  old_watches=$(json_string_field DIRENV_WATCHES "$first_json")
  test -f "$first_apply"

  sleep 1
  cat >"$project_dir/overlay/task.nu" <<'EOF'
export def reload_watched [] { "two" }
EOF

  (
    cd "$project_dir"
    env \
      DIRENV_NU_OVERLAY_APPLY="$first_apply" \
      DIRENV_DIFF="$old_diff" \
      DIRENV_DIR="$old_dir" \
      DIRENV_FILE="$old_file" \
      DIRENV_WATCHES="$old_watches" \
      "$DIRENV" export json >"$second_json"
  )
  second_apply=$(json_string_field DIRENV_NU_OVERLAY_APPLY "$second_json")
  test -f "$second_apply"
  test "$first_apply" != "$second_apply"
  run_nu --commands 'source '"$(nu_quote "$second_apply")"'; if (reload_watched) != "two" { error make { msg: "changed overlay module behavior did not load" } }'
}

assert_direnv_blocked_envrc_unloads_apply() {
  local project_dir="$TMPDIR/blocked-envrc"
  local allowed_json="$TMPDIR/blocked-envrc-allowed.json"
  local blocked_json="$TMPDIR/blocked-envrc-blocked.json"
  local blocked_err="$TMPDIR/blocked-envrc-blocked.err"
  local old_apply old_diff old_dir old_file old_watches

  mkdir -p "$project_dir/overlay"
  cat >"$project_dir/.envrc" <<'EOF'
export BLOCKED_ENVRC_MARK=allowed
use nu-overlay overlay/task.nu
EOF
  cat >"$project_dir/overlay/task.nu" <<'EOF'
export def blocked_envrc [] { "allowed" }
EOF
  allow_fixture "$project_dir"

  direnv_json_for "$project_dir" "$allowed_json"
  old_apply=$(json_string_field DIRENV_NU_OVERLAY_APPLY "$allowed_json")
  old_diff=$(json_string_field DIRENV_DIFF "$allowed_json")
  old_dir=$(json_string_field DIRENV_DIR "$allowed_json")
  old_file=$(json_string_field DIRENV_FILE "$allowed_json")
  old_watches=$(json_string_field DIRENV_WATCHES "$allowed_json")
  test -f "$old_apply"

  sleep 1
  cat >"$project_dir/.envrc" <<'EOF'
export BLOCKED_ENVRC_MARK=blocked
use nu-overlay overlay/task.nu
EOF

  (
    cd "$project_dir"
    env \
      BLOCKED_ENVRC_MARK=allowed \
      DIRENV_NU_OVERLAY_APPLY="$old_apply" \
      DIRENV_DIFF="$old_diff" \
      DIRENV_DIR="$old_dir" \
      DIRENV_FILE="$old_file" \
      DIRENV_WATCHES="$old_watches" \
      "$DIRENV" export json >"$blocked_json" 2>"$blocked_err" || true
  )

  assert_file_contains "$blocked_json" '"DIRENV_NU_OVERLAY_APPLY": null' "blocked .envrc did not clear stale apply path"
  assert_file_contains "$blocked_json" '"BLOCKED_ENVRC_MARK": null' "blocked .envrc did not unload old exported env"
  assert_file_contains "$blocked_err" 'is blocked' "blocked .envrc did not report direnv trust error"
}

assert_direnv_invalid_after_valid_cleans_partial_apply() {
  local project_dir="$TMPDIR/invalid-after-valid"
  local out="$project_dir/export.json"
  local err="$project_dir/export.err"

  mkdir -p "$project_dir/overlay"
  cat >"$project_dir/.envrc" <<'EOF'
use nu-overlay overlay/good.nu
use nu-overlay missing.nu
EOF
  cat >"$project_dir/overlay/good.nu" <<'EOF'
export def good_before_failure [] { "good" }
EOF
  allow_fixture "$project_dir"

  (
    cd "$project_dir"
    "$DIRENV" export json >"$out" 2>"$err" || true
  )

  assert_file_not_contains "$out" 'DIRENV_NU_OVERLAY_APPLY' "invalid declaration after valid one leaked apply env"
  assert_file_contains "$err" 'nu overlay file not found' "invalid declaration after valid one did not report missing overlay"
}

assert_direnv_failure_does_not_remove_inherited_internal_dir() {
  local project_dir="$TMPDIR/inherited-internal-dir"
  local inherited_dir="$TMPDIR/inherited-internal-dir-must-survive"
  local out="$project_dir/export.json"
  local err="$project_dir/export.err"

  mkdir -p "$project_dir" "$inherited_dir"
  cat >"$project_dir/.envrc" <<'EOF'
use nu-overlay missing.nu
EOF
  allow_fixture "$project_dir"

  (
    cd "$project_dir"
    env __NU_DIRENV_OVERLAY_DIR="$inherited_dir" \
      "$DIRENV" export json >"$out" 2>"$err" || true
  )

  test -d "$inherited_dir"
  assert_file_not_contains "$out" 'DIRENV_NU_OVERLAY_APPLY' "invalid declaration leaked apply env with inherited internal dir"
  assert_file_contains "$err" 'nu overlay file not found' "invalid declaration did not report missing overlay with inherited internal dir"
}

assert_direnv_invalid_overlay_api_cleans_apply() {
  local missing="$TMPDIR/invalid-missing"
  local explicit="$TMPDIR/invalid-explicit-name"
  local glob="$TMPDIR/invalid-glob"
  local zero_args="$TMPDIR/invalid-zero-args"
  local two_args="$TMPDIR/invalid-two-args"

  mkdir -p "$missing" "$explicit/overlay" "$glob/overlay" "$zero_args" "$two_args/overlay"
  cat >"$missing/.envrc" <<'EOF'
use nu-overlay missing.nu
EOF
  cat >"$explicit/.envrc" <<'EOF'
use nu-overlay overlay/task=custom.nu
EOF
  touch "$explicit/overlay/task=custom.nu"
  cat >"$glob/.envrc" <<'EOF'
use nu-overlay "overlay/*.nu"
EOF
  touch "$glob/overlay/task.nu"
  cat >"$zero_args/.envrc" <<'EOF'
use nu-overlay
EOF
  cat >"$two_args/.envrc" <<'EOF'
use nu-overlay overlay/a.nu overlay/b.nu
EOF
  touch "$two_args/overlay/a.nu" "$two_args/overlay/b.nu"

  allow_fixture "$missing"
  allow_fixture "$explicit"
  allow_fixture "$glob"
  allow_fixture "$zero_args"
  allow_fixture "$two_args"

  assert_direnv_export_has_no_apply "$missing" "missing overlay"
  assert_direnv_export_has_no_apply "$explicit" "explicit overlay name"
  assert_direnv_export_has_no_apply "$glob" "glob overlay path"
  assert_direnv_export_has_no_apply "$zero_args" "zero-argument overlay"
  assert_direnv_export_has_no_apply "$two_args" "two-argument overlay"
}

run_direnv_api_regressions() {
  assert_direnv_generated_apply_shape "$TMPDIR/project"
  assert_direnv_duplicate_overlay_is_idempotent
  assert_direnv_duplicate_overlay_canonical_paths_are_idempotent
  assert_direnv_quoted_overlay_paths_source_successfully
  assert_direnv_overlay_module_change_rebuilds_apply
  assert_direnv_blocked_envrc_unloads_apply
  assert_direnv_invalid_after_valid_cleans_partial_apply
  assert_direnv_failure_does_not_remove_inherited_internal_dir
  assert_direnv_invalid_overlay_api_cleans_apply
}
