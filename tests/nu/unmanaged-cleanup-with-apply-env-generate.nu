use std/assert

source $autoload
open $inherited_json | load-env
source $apply
cd $tmpdir
$env.DIRENV_NU_OVERLAY_APPLY = ""

__nu-direnv-overlay write-source --cleanup-only
let wrapper = (wrapper-path)
let body = (open $wrapper)

assert ($body | str contains 'hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors') "cleanup wrapper did not hide stale apply env"
assert ($body | str contains '$env.DIRENV_NU_OVERLAY_APPLY = ""') "cleanup wrapper did not leave null apply as empty string"
assert not ($body | str contains $"source ($apply)") "cleanup wrapper re-sourced stale apply"

$wrapper
