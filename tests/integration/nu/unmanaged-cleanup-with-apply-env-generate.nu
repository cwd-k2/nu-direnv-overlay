use std/assert

source $autoload
open $inherited_json | load-env
source $apply
cd $tmpdir
$env.DIRENV_NU_OVERLAY_APPLY = ""

let cleanup_plan = (__nu-direnv-overlay wrapper-plan --cleanup-only)
assert equal $cleanup_plan.type cleanup "cleanup-only wrapper did not choose cleanup plan"
assert equal (
  $cleanup_plan.actions | where type == line and source == 'hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors' | length
) 1 "cleanup plan did not hide stale apply env"
assert equal (
  $cleanup_plan.actions | where type == line and source == '$env.DIRENV_NU_OVERLAY_APPLY = ""' | length
) 1 "cleanup plan did not leave null apply as empty string"
assert equal (
  $cleanup_plan.actions | where type == source_apply | length
) 0 "cleanup plan re-sourced stale apply"

__nu-direnv-overlay write-source --cleanup-only
wrapper-path
