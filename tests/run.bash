#!/usr/bin/env bash
set -eu

: "${PKG:?}"
: "${NU:?}"
: "${DIRENV:?}"
: "${TMPDIR:?}"

test_dir=${TEST_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}

. "$test_dir/harness.bash"
. "$test_dir/fixtures.bash"
. "$test_dir/direnv-api.bash"
. "$test_dir/repl.bash"

setup_fixtures() {
  create_standard_fixtures
  allow_standard_fixtures
  create_path_fixture "$TMPDIR/path fixture"
  allow_fixture "$TMPDIR/path fixture"

  apply=$(apply_path_for "$TMPDIR/project")
  nested_apply=$(apply_path_for "$TMPDIR/nested/child")
  path_fixture_apply=$(apply_path_for "$TMPDIR/path fixture")
  test -f "$apply"
  test -f "$nested_apply"
  test -f "$path_fixture_apply"

  direnv_json_for "$TMPDIR/project" "$TMPDIR/inherited.json"
  direnv_json_for "$TMPDIR/project" "$TMPDIR/inherited-again.json"
  direnv_json_for "$TMPDIR/project-b" "$TMPDIR/inherited-b.json"
  direnv_json_for "$TMPDIR/path fixture" "$TMPDIR/path-fixture.json"
}

run_installation_and_unit_tests() {
  # User story: installation exposes the helper files and hook installation is
  # repeatable without disturbing unrelated user hooks.
  assert_installed_files
  assert_direnv_api
  assert_nu_autoload
  run_nu_test hooks
}

run_direnv_generation_tests() {
  # User story: .envrc declarations generate deterministic, cleanup-aware
  # apply files, while unsupported declarations fail without stale apply state.
  run_direnv_api_regressions
  run_nu_test apply apply "$apply"
  run_nu_test source-up apply "$nested_apply"
  run_nu_test path-fixture \
    apply "$path_fixture_apply" \
    path_fixture_json "$TMPDIR/path-fixture.json" \
    path_fixture_dir "$TMPDIR/path fixture"
}

run_hook_entrypoint_tests() {
  # User story: both automatic hook sync and manual reload expose the same
  # project overlay commands before the next user command resolves.
  hook_apply=$(
    cd "$TMPDIR/project"
    run_nu_test_stdout inherited-sync inherited_json "$TMPDIR/inherited.json"
  )
  test -f "$hook_apply"
  run_nu_test wrapper-apply apply "$hook_apply"
  run_nu_test wrapper-plan inherited_json "$TMPDIR/inherited.json"

  reloaded_apply=$(
    cd "$TMPDIR/project"
    run_nu_test_stdout manual-reload inherited_json "$TMPDIR/inherited.json"
  )
  test -f "$reloaded_apply"
  run_nu_test wrapper-apply apply "$reloaded_apply"
  run_nu_test status-side-effect-free \
    inherited_json "$TMPDIR/inherited.json" \
    apply "$reloaded_apply"
  last_exit_wrapper=$(
    run_nu_test_stdout sync-preserves-last-exit-code-generate \
      inherited_json "$TMPDIR/inherited.json"
  )
  run_nu_test sync-preserves-last-exit-code \
    inherited_json "$TMPDIR/inherited.json" \
    wrapper "$last_exit_wrapper"
}

run_wrapper_transition_tests() {
  # User story: common navigation patterns preserve cwd, remove stale commands,
  # and keep current direnv environment after cleanup and project switches.
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

  run_nu_test stale-cleanup \
    apply "$reloaded_apply" \
    cleanup "$stale_cleanup"

  run_nu_test repeated-cleanup-pwd \
    apply "$reloaded_apply" \
    cleanup "$stale_cleanup"

  unmanaged_cleanup_with_apply_env=$(
    run_nu_test_stdout unmanaged-cleanup-with-apply-env-generate \
      inherited_json "$TMPDIR/inherited.json" \
      apply "$reloaded_apply"
  )
  run_nu_test unmanaged-cleanup-with-apply-env \
    inherited_json "$TMPDIR/inherited.json" \
    apply "$reloaded_apply" \
    wrapper "$unmanaged_cleanup_with_apply_env"

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
}

init_test_env
run_installation_and_unit_tests
setup_fixtures
run_direnv_generation_tests
run_hook_entrypoint_tests
run_wrapper_transition_tests

# User story: interactive shells see the same state at prompt time, command
# time, and real Reedline path completion.
run_repl_regressions
