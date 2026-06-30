use std/assert

source $autoload
open $inherited_json | load-env
source $apply
hide-env LAST_EXIT_CODE --ignore-errors

__nu-direnv-overlay write-source

let wrapper = (wrapper-path)
assert ($wrapper | path exists) "last-exit-code unset wrapper was not created"
assert (($wrapper | open) | str contains "__NU_DIRENV_OVERLAY_LAST_EXIT_CODE") "wrapper did not record last-exit-code restoration guard"
$wrapper
