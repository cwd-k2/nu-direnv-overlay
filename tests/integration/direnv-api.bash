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

assert_direnv_invalid_overlay_api_cleans_apply() {
  local missing="$TMPDIR/invalid-missing"
  local explicit="$TMPDIR/invalid-explicit-name"
  local glob="$TMPDIR/invalid-glob"

  mkdir -p "$missing" "$explicit/overlay" "$glob/overlay"
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

  allow_fixture "$missing"
  allow_fixture "$explicit"
  allow_fixture "$glob"

  assert_direnv_export_has_no_apply "$missing" "missing overlay"
  assert_direnv_export_has_no_apply "$explicit" "explicit overlay name"
  assert_direnv_export_has_no_apply "$glob" "glob overlay path"
}

run_direnv_api_regressions() {
  assert_direnv_generated_apply_shape "$TMPDIR/project"
  assert_direnv_duplicate_overlay_is_idempotent
  assert_direnv_invalid_overlay_api_cleans_apply
}
