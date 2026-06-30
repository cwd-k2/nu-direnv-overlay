use std/assert

source $autoload

# Apply plans run when direnv exposes a real generated apply file. They must
# clean stale overlay state first, then source the new file without reverting
# export-env changes from the overlay being applied.
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
) 0 "apply plan should not restore environment after sourcing a new overlay"

# A new apply can replace a previous project or a rebuilt .envrc. Tracked
# overlays and exports from the old state must be removed before sourcing.
$env.NU_DIRENV_OVERLAY_ACTIVE = "nu-direnv-unit-a;nu-direnv-unit-b"
$env.NU_DIRENV_OVERLAY_EXPORTS = (["unit_build" "unit_st"] | str join (char us))

let apply_with_cleanup_plan = (__nu-direnv-overlay wrapper-plan)
assert equal $apply_with_cleanup_plan.type apply "apply plan with tracked state did not choose apply"
assert equal (
  $apply_with_cleanup_plan.actions | where type == hide_overlay | length
) 2 "apply plan did not include tracked overlay cleanup"
assert equal (
  $apply_with_cleanup_plan.actions | where type == hide_export | length
) 2 "apply plan did not include tracked export cleanup"
assert equal (
  $apply_with_cleanup_plan.actions | where type == source_apply | length
) 1 "apply plan did not source apply after cleanup"
