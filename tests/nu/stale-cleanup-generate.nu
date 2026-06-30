source $autoload
source $apply
hide-env NU_DIRENV_OVERLAY_ACTIVE --ignore-errors
hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
hide-env PROJECT_ROOT --ignore-errors
$env.PROJECT_MARK = "outside"
$env.NU_DIRENV_OVERLAY_KEEP_ENV_TEST = "outside"
$env.PROMPT_COMMAND = {|| "prompt" }
__nu-direnv-overlay write-source --cleanup-only
wrapper-path
