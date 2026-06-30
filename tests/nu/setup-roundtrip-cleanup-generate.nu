source $autoload
source $apply
hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
hide-env NU_DIRENV_OVERLAY_EXPORTS --ignore-errors
hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
hide-env PROJECT_ROOT --ignore-errors
__nu-direnv-overlay write-source --cleanup-only
wrapper-path
