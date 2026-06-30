source $autoload

open $inherited_json | load-env
source $apply_a

hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
__nu-direnv-overlay write-source --cleanup-only
open (wrapper-path) | save --force $cleanup_wrapper
source $cleanup_wrapper

open $inherited_b_json | load-env
__nu-direnv-overlay write-source
open (wrapper-path) | save --force $apply_b_wrapper
