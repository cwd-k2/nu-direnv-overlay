use std/assert

source $apply

assert equal (nested_parent) "parent" "source_up parent overlay did not load"
assert equal (nested_child) "child" "child overlay did not load"
assert-active-overlay-count 2 "unexpected active overlay count for nested source_up project"
