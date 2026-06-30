use std/assert

open $inherited_json | load-env
source $apply
cd $tmpdir
$env.DIRENV_NU_OVERLAY_APPLY = ""
source $wrapper

assert equal ($env.DIRENV_NU_OVERLAY_APPLY? | default "") "" "cleanup did not normalize stale apply env"
assert-command-hidden "build" "cleanup did not hide build after null apply"
assert-command-hidden "st" "cleanup did not hide st after null apply"
