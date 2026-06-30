use std/assert

source $apply

assert equal (build) "built" "build command did not load"
assert equal (st) "status" "st command did not load"
assert (
  overlay list
  | where name =~ '^nu-direnv-'
  | is-not-empty
) "nu-direnv overlay names were not created"
