use std/assert

source $apply
cd $tmpdir
hide-env PROJECT_ROOT --ignore-errors
$env.PROJECT_MARK = "outside"
$env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST = "outside"
$env.PROMPT_COMMAND = {|| "prompt" }
source $cleanup

assert equal $env.PWD $tmpdir "cleanup changed PWD while hiding overlay"
assert equal ($env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST? | default "") "outside" "cleanup restored environment while hiding overlay"
assert equal ($env.PROJECT_ROOT? | default "") "" "cleanup resurrected unloaded direnv environment"
assert equal ($env.PROJECT_MARK? | default "") "outside" "cleanup did not preserve same-named current env value"
assert equal (do $env.PROMPT_COMMAND) "prompt" "cleanup removed prompt closure"
assert-command-hidden "build" "overlay build command remained visible after cleanup"
assert-command-hidden "st" "overlay st command remained visible after cleanup"
assert-no-active-overlays
