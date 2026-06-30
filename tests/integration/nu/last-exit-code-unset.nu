use std/assert

source $apply
hide-env LAST_EXIT_CODE --ignore-errors
source $wrapper

assert equal ($env.LAST_EXIT_CODE? | default null) null "wrapper created LAST_EXIT_CODE when it was unset"
assert equal ($env.__NU_DIRENV_OVERLAY_LAST_EXIT_CODE? | default null) null "wrapper left temporary last-exit-code env"
