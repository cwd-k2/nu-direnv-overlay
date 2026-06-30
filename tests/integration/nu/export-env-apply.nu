use std/assert

source $autoload
source $assert_file

$env.EXPORT_ENV_MARK = "before"
source $apply_wrapper

assert equal $env.EXPORT_ENV_MARK "overlay" "overlay export-env did not update an existing env value"
assert equal $env.EXPORT_ENV_NEW "new" "overlay export-env did not create a new env value"

source $cleanup_wrapper

assert equal $env.EXPORT_ENV_MARK "before" "cleanup did not restore env value changed by overlay export-env"
assert equal ($env.EXPORT_ENV_NEW? | default null) null "cleanup did not remove env value created by overlay export-env"
