source $autoload
source $apply
hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
hide-env PROJECT_ROOT --ignore-errors
$env.PROJECT_MARK = "outside"
$env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST = "outside"
$env.PROMPT_COMMAND = {|| "prompt" }

let cleanup_plan = (__nu-direnv-overlay wrapper-plan --cleanup-only)
assert equal $cleanup_plan.type cleanup "stale cleanup did not choose cleanup plan"
assert equal (
  $cleanup_plan.actions | where type == hide_overlay | length
) 0 "prompt cleanup should defer active overlay hide"
assert equal (
  $cleanup_plan.actions | where type == source_apply | length
) 0 "cleanup unexpectedly planned to re-source an old apply file"
for exported in [build project_name nested st] {
  assert equal (
    $cleanup_plan.actions | where type == hide_export and name == $exported | length
  ) 1 $"cleanup did not plan to hide ($exported)"
}

__nu-direnv-overlay write-source --cleanup-only
wrapper-path
