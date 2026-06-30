use std/assert

source $autoload

# Cleanup-only plans run after direnv has stopped exposing an apply file. They
# hide tracked exports immediately, but leave active overlay frames for the next
# apply path so prompt-time cleanup does not disturb Reedline cwd completion.
$env.NU_DIRENV_OVERLAY_ACTIVE = "nu-direnv-unit-a;nu-direnv-unit-b"
$env.NU_DIRENV_OVERLAY_EXPORTS = (["unit_build" "unit_st"] | str join (char us))
$env.NU_DIRENV_OVERLAY_ENV_NAMES = (["UNIT_ENV_OLD" "UNIT_ENV_NEW"] | str join (char us))
$env.NU_DIRENV_OVERLAY_ENV_BEFORE = { UNIT_ENV_OLD: "before" } | to nuon
$env.NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES = [UNIT_ENV_OLD] | to nuon

let cleanup_plan = (__nu-direnv-overlay wrapper-plan --cleanup-only)
assert equal $cleanup_plan.type cleanup "cleanup-only wrapper plan did not choose cleanup"
assert equal (
  $cleanup_plan.actions | where type == line and source == 'hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors' | length
) 1 "cleanup plan did not hide stale apply state"
assert equal (
  $cleanup_plan.actions | where type == line and source == '$env.NU_DIRENV_OVERLAY_ACTIVE = ""' | length
) 1 "cleanup plan did not reset active overlay tracking"
assert equal (
  $cleanup_plan.actions | where type == hide_overlay | length
) 0 "cleanup-only plan should not hide active overlay frames"
assert equal (
  $cleanup_plan.actions | where type == hide_export | length
) 2 "cleanup-only plan did not hide tracked exports"
assert equal (
  $cleanup_plan.actions | where type == restore_overlay_env | length
) 1 "cleanup-only plan did not restore tracked overlay env"
assert equal (
  $cleanup_plan.actions | where type == line and source == '$env.NU_DIRENV_OVERLAY_ENV_NAMES = ""' | length
) 1 "cleanup plan did not reset overlay env names marker"

# A stale apply path that no longer exists means the shell is leaving or between
# projects. The wrapper should clean markers instead of trying to source it.
$env.DIRENV_NU_OVERLAY_APPLY = ($tmpdir | path join "unit-wrapper-plan-missing-apply.nu")
hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
hide-env NU_DIRENV_OVERLAY_EXPORTS --ignore-errors
hide-env NU_DIRENV_OVERLAY_ENV_NAMES --ignore-errors
hide-env NU_DIRENV_OVERLAY_ENV_BEFORE --ignore-errors
hide-env NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES --ignore-errors
$env.NU_DIRENV_OVERLAY_APPLY_LOADED = ($tmpdir | path join "unit-wrapper-plan-old-apply.nu")
$env.NU_DIRENV_OVERLAY_APPLY_PWD = (pwd)

let missing_apply_cleanup_plan = (__nu-direnv-overlay wrapper-plan)
assert equal $missing_apply_cleanup_plan.type cleanup "missing apply path did not choose cleanup"
assert equal $missing_apply_cleanup_plan.apply $env.DIRENV_NU_OVERLAY_APPLY "missing apply plan did not record stale apply path"
assert equal (
  $missing_apply_cleanup_plan.actions | where type == hide_overlay | length
) 0 "missing apply cleanup should defer active overlay frame cleanup"
assert equal (
  $missing_apply_cleanup_plan.actions | where type == line and source == '$env.NU_DIRENV_OVERLAY_APPLY_LOADED = ""' | length
) 1 "missing apply cleanup did not reset loaded marker"
assert equal (
  $missing_apply_cleanup_plan.actions | where type == line and source == '$env.NU_DIRENV_OVERLAY_APPLY_PWD = ""' | length
) 1 "missing apply cleanup did not reset apply cwd marker"

# With no apply path and no tracked state, wrapper generation should be empty.
hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
hide-env NU_DIRENV_OVERLAY_EXPORTS --ignore-errors
hide-env NU_DIRENV_OVERLAY_ENV_NAMES --ignore-errors
hide-env NU_DIRENV_OVERLAY_ENV_BEFORE --ignore-errors
hide-env NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES --ignore-errors
hide-env NU_DIRENV_OVERLAY_APPLY_LOADED --ignore-errors
hide-env NU_DIRENV_OVERLAY_APPLY_PWD --ignore-errors

let noop_plan = (__nu-direnv-overlay wrapper-plan)
assert equal $noop_plan.type noop "wrapper plan did not no-op without apply or stale state"
assert equal ($noop_plan.actions | length) 0 "noop wrapper plan included actions"
