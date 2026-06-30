source $autoload
source $assert_file

$env.EXPORT_ENV_MARK = "before"
$env.DIRENV_NU_OVERLAY_APPLY = $apply
__nu-direnv-overlay write-source
open (wrapper-path) | save --force $apply_wrapper

source $apply
$env.DIRENV_NU_OVERLAY_APPLY = ""
__nu-direnv-overlay write-source --cleanup-only
open (wrapper-path) | save --force $cleanup_wrapper
