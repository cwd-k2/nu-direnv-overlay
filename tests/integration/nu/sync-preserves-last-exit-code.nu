use std/assert

$env.LAST_EXIT_CODE = 37
source $wrapper

assert equal $env.LAST_EXIT_CODE 37 "sourcing generated wrapper changed LAST_EXIT_CODE"
