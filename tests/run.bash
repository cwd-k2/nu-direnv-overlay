#!/usr/bin/env bash
set -eu

: "${PKG:?}"
: "${NU:?}"
: "${DIRENV:?}"
: "${TMPDIR:?}"

test_dir=${TEST_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}

. "$test_dir/harness.bash"
. "$test_dir/fixtures.bash"
. "$test_dir/repl.bash"

init_test_env
assert_installed_files
assert_direnv_api
assert_nu_autoload
run_nu_test hooks

create_standard_fixtures
allow_standard_fixtures

apply=$(apply_path_for "$TMPDIR/project")
test -f "$apply"
run_nu_test apply apply "$apply"

nested_apply=$(apply_path_for "$TMPDIR/nested/child")
test -f "$nested_apply"
run_nu_test source-up apply "$nested_apply"

direnv_json_for "$TMPDIR/project" "$TMPDIR/inherited.json"
direnv_json_for "$TMPDIR/project" "$TMPDIR/inherited-again.json"
direnv_json_for "$TMPDIR/project-b" "$TMPDIR/inherited-b.json"

hook_apply=$(
  cd "$TMPDIR/project"
  run_nu_test_stdout inherited-sync inherited_json "$TMPDIR/inherited.json"
)
test -f "$hook_apply"
run_nu_test wrapper-apply apply "$hook_apply"

reloaded_apply=$(
  cd "$TMPDIR/project"
  run_nu_test_stdout manual-reload inherited_json "$TMPDIR/inherited.json"
)
test -f "$reloaded_apply"
run_nu_test wrapper-apply apply "$reloaded_apply"

same_project_wrapper=$(
  run_nu_test_stdout same-project-generate \
    inherited_json "$TMPDIR/inherited.json" \
    apply "$reloaded_apply"
)
run_nu_test same-project \
  inherited_json "$TMPDIR/inherited.json" \
  apply "$reloaded_apply" \
  wrapper "$same_project_wrapper"

run_nu_test command-cd-preserved \
  inherited_json "$TMPDIR/inherited.json" \
  apply "$reloaded_apply"

changed_apply_after_cd_wrapper=$(
  run_nu_test_stdout changed-apply-after-cd-generate \
    inherited_json "$TMPDIR/inherited.json" \
    inherited_again_json "$TMPDIR/inherited-again.json" \
    apply "$reloaded_apply"
)
run_nu_test changed-apply-after-cd \
  inherited_json "$TMPDIR/inherited.json" \
  inherited_again_json "$TMPDIR/inherited-again.json" \
  apply "$reloaded_apply" \
  wrapper "$changed_apply_after_cd_wrapper"

project_to_project_wrapper=$(
  run_nu_test_stdout project-to-project-generate \
    inherited_b_json "$TMPDIR/inherited-b.json" \
    apply_a "$reloaded_apply"
)
run_nu_test project-to-project \
  inherited_b_json "$TMPDIR/inherited-b.json" \
  apply_a "$reloaded_apply" \
  wrapper "$project_to_project_wrapper"

stale_cleanup=$(
  run_nu_test_stdout stale-cleanup-generate apply "$reloaded_apply"
)
assert_file_not_contains "$stale_cleanup" 'overlay hide --keep-env .*"nu-direnv-' "unmanaged cleanup should defer active overlay hide"
assert_file_not_contains "$stale_cleanup" '^source ' "cleanup unexpectedly re-sourced an old apply file"
for exported in build project_name nested st; do
  assert_file_contains "$stale_cleanup" "hide \"$exported\"" "cleanup did not hide $exported"
done

run_nu_test stale-cleanup \
  apply "$reloaded_apply" \
  cleanup "$stale_cleanup"

run_nu_test repeated-cleanup-pwd \
  apply "$reloaded_apply" \
  cleanup "$stale_cleanup"

setup_roundtrip_cleanup=$(
  run_nu_test_stdout setup-roundtrip-cleanup-generate apply "$reloaded_apply"
)
setup_roundtrip_apply=$(
  run_nu_test_stdout setup-roundtrip-apply-generate inherited_json "$TMPDIR/inherited.json"
)
run_nu_test setup-roundtrip \
  inherited_json "$TMPDIR/inherited.json" \
  inherited_b_json "$TMPDIR/inherited-b.json" \
  apply_a "$reloaded_apply" \
  cleanup "$setup_roundtrip_cleanup" \
  apply_again "$setup_roundtrip_apply" \
  project_to_project "$project_to_project_wrapper"

run_repl_regressions
