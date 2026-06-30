#!/usr/bin/env bash
set -eu

: "${PKG:?}"
: "${NU:?}"
: "${DIRENV:?}"
: "${TMPDIR:?}"

test_dir=${TEST_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}

. "$test_dir/support/harness.bash"
. "$test_dir/support/fixtures.bash"
. "$test_dir/integration/direnv-api.bash"
. "$test_dir/e2e/repl.bash"

setup_integration_fixtures() {
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

run_integration_installation_tests() {
  # User story: installation exposes the helper files and direnv/Nushell entry
  # points without requiring project fixtures.
  assert_installed_files
  assert_direnv_api
  assert_nu_autoload
}

run_unit_tests() {
  # User story: local Nushell helpers preserve unrelated user hook config while
  # installing the sync/source pair idempotently.
  run_nu_test unit hooks
  run_nu_test unit wrapper-apply-plan
  run_nu_test unit wrapper-cleanup-plan
}

run_integration_direnv_generation_tests() {
  # User story: .envrc declarations generate deterministic, cleanup-aware
  # apply files, while unsupported declarations fail without stale apply state.
  run_direnv_api_regressions
  run_nu_test integration apply apply "$apply"
  run_nu_test integration source-up apply "$nested_apply"
  run_nu_test integration path-fixture \
    apply "$path_fixture_apply" \
    path_fixture_json "$TMPDIR/path-fixture.json" \
    path_fixture_dir "$TMPDIR/path fixture"
}

run_integration_hook_entrypoint_tests() {
  # User story: both automatic hook sync and manual reload expose the same
  # project overlay commands before the next user command resolves.
  hook_apply=$(
    cd "$TMPDIR/project"
    run_nu_test_stdout integration inherited-sync inherited_json "$TMPDIR/inherited.json"
  )
  test -f "$hook_apply"
  run_nu_test integration wrapper-apply apply "$hook_apply"

  reloaded_apply=$(
    cd "$TMPDIR/project"
    run_nu_test_stdout integration manual-reload inherited_json "$TMPDIR/inherited.json"
  )
  test -f "$reloaded_apply"
  run_nu_test integration wrapper-apply apply "$reloaded_apply"
  run_nu_test integration status-side-effect-free \
    inherited_json "$TMPDIR/inherited.json" \
    apply "$reloaded_apply"
  last_exit_wrapper=$(
    run_nu_test_stdout integration sync-preserves-last-exit-code-generate \
      inherited_json "$TMPDIR/inherited.json"
  )
  run_nu_test integration sync-preserves-last-exit-code \
    inherited_json "$TMPDIR/inherited.json" \
    wrapper "$last_exit_wrapper"
}

run_integration_wrapper_transition_tests() {
  # User story: common navigation patterns preserve cwd, remove stale commands,
  # and keep current direnv environment after cleanup and project switches.
  same_project_wrapper=$(
    run_nu_test_stdout integration same-project-generate \
      inherited_json "$TMPDIR/inherited.json" \
      apply "$reloaded_apply"
  )
  run_nu_test integration same-project \
    inherited_json "$TMPDIR/inherited.json" \
    apply "$reloaded_apply" \
    wrapper "$same_project_wrapper"

  run_nu_test integration command-cd-preserved \
    inherited_json "$TMPDIR/inherited.json" \
    apply "$reloaded_apply"

  changed_apply_after_cd_wrapper=$(
    run_nu_test_stdout integration changed-apply-after-cd-generate \
      inherited_json "$TMPDIR/inherited.json" \
      inherited_again_json "$TMPDIR/inherited-again.json" \
      apply "$reloaded_apply"
  )
  run_nu_test integration changed-apply-after-cd \
    inherited_json "$TMPDIR/inherited.json" \
    inherited_again_json "$TMPDIR/inherited-again.json" \
    apply "$reloaded_apply" \
    wrapper "$changed_apply_after_cd_wrapper"

  project_to_project_wrapper=$(
    run_nu_test_stdout integration project-to-project-generate \
      inherited_b_json "$TMPDIR/inherited-b.json" \
      apply_a "$reloaded_apply"
  )
  run_nu_test integration project-to-project \
    inherited_b_json "$TMPDIR/inherited-b.json" \
    apply_a "$reloaded_apply" \
    wrapper "$project_to_project_wrapper"

  stale_cleanup=$(
    run_nu_test_stdout integration stale-cleanup-generate apply "$reloaded_apply"
  )

  run_nu_test integration stale-cleanup \
    apply "$reloaded_apply" \
    cleanup "$stale_cleanup"

  run_nu_test integration repeated-cleanup-pwd \
    apply "$reloaded_apply" \
    cleanup "$stale_cleanup"

  unmanaged_cleanup_with_apply_env=$(
    run_nu_test_stdout integration unmanaged-cleanup-with-apply-env-generate \
      inherited_json "$TMPDIR/inherited.json" \
      apply "$reloaded_apply"
  )
  run_nu_test integration unmanaged-cleanup-with-apply-env \
    inherited_json "$TMPDIR/inherited.json" \
    apply "$reloaded_apply" \
    wrapper "$unmanaged_cleanup_with_apply_env"

  setup_roundtrip_cleanup=$(
    run_nu_test_stdout integration setup-roundtrip-cleanup-generate apply "$reloaded_apply"
  )
  setup_roundtrip_apply=$(
    run_nu_test_stdout integration setup-roundtrip-apply-generate inherited_json "$TMPDIR/inherited.json"
  )
  run_nu_test integration setup-roundtrip \
    inherited_json "$TMPDIR/inherited.json" \
    inherited_b_json "$TMPDIR/inherited-b.json" \
    apply_a "$reloaded_apply" \
    cleanup "$setup_roundtrip_cleanup" \
    apply_again "$setup_roundtrip_apply" \
    project_to_project "$project_to_project_wrapper"
}

init_test_env
run_integration_installation_tests
run_unit_tests
setup_integration_fixtures
run_integration_direnv_generation_tests
run_integration_hook_entrypoint_tests
run_integration_wrapper_transition_tests

# User story: interactive shells see the same state at prompt time, command
# time, and real Reedline path completion.
run_repl_regressions
