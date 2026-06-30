use std/assert

source $autoload

let apply = ($tmpdir | path join "unit-wrapper-plan-apply.nu")
"" | save --force $apply
$env.DIRENV_NU_OVERLAY_APPLY = $apply

let apply_plan = (__nu-direnv-overlay wrapper-plan)
assert equal $apply_plan.type apply "wrapper plan did not choose apply for an existing apply file"
assert equal $apply_plan.apply $apply "wrapper plan did not record the apply path"
assert equal (
  $apply_plan.actions | where type == source_apply | length
) 1 "apply plan did not include one source action"
assert equal (
  $apply_plan.actions | where type == mark_apply_pwd | length
) 1 "apply plan did not record the apply cwd marker"
assert equal (
  $apply_plan.actions | where type == load_env | length
) 1 "apply plan did not include environment restoration"

let cleanup_plan = (__nu-direnv-overlay wrapper-plan --cleanup-only)
assert equal $cleanup_plan.type cleanup "cleanup-only wrapper plan did not choose cleanup"
assert equal (
  $cleanup_plan.actions | where type == line and source == 'hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors' | length
) 1 "cleanup plan did not hide stale apply state"
assert equal (
  $cleanup_plan.actions | where type == line and source == '$env.NU_DIRENV_OVERLAY_ACTIVE = ""' | length
) 1 "cleanup plan did not reset active overlay tracking"
