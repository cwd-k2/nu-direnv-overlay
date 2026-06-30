source $apply
use std/assert

assert equal (build) "built" "build command did not load"
assert equal (st) "status" "st command did not load"
