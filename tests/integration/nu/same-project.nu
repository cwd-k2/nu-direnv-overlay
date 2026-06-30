use std/assert

source $autoload
open $inherited_json | load-env
source $apply
source $wrapper

assert equal (build) "built" "build command did not load"
assert equal (st) "status" "st command did not load"
assert equal (nu-direnv-overlay status | get active | length) 2 "unexpected active overlay count after same-project no-op"
