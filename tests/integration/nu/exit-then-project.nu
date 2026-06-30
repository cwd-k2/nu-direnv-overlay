use std/assert

source $autoload

open $inherited_json | load-env
source $apply_a

hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
source $cleanup_wrapper

assert-active-overlay-count 2 "cleanup should defer project A overlay frame cleanup"
assert equal (
  $env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "" | length
) 2 "cleanup dropped active overlay markers needed by the next apply"

open $inherited_b_json | load-env
source $apply_b_wrapper

assert equal (build) "built-b" "project B build command did not load after leaving project A"
assert equal (b_only) "b-only" "project B unique command did not load after leaving project A"
assert-command-hidden "st" "project A command leaked after entering project B"
let status = (nu-direnv-overlay status)
assert equal ($status.active | length) 1 "unexpected active overlay marker count after exit-then-project"
assert equal ($status.active_frames | length) 1 "unexpected active overlay frame count after exit-then-project"
assert equal ($status.active | sort) ($status.active_frames | sort) "active overlay markers did not match active frames"
