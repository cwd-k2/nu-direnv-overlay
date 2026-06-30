use std/assert

source $autoload
open $inherited_json | load-env
source $apply

let before = {
  pwd: $env.PWD
  active: (overlay list | where name =~ '^nu-direnv-' and active == true | get name | sort)
  wrapper_exists: (wrapper-path | path exists)
  build_visible: (scope commands | where name == build | is-not-empty)
}

let status = (nu-direnv-overlay status)
let after = {
  pwd: $env.PWD
  active: (overlay list | where name =~ '^nu-direnv-' and active == true | get name | sort)
  wrapper_exists: (wrapper-path | path exists)
  build_visible: (scope commands | where name == build | is-not-empty)
}

assert equal $status.apply $apply "status reported the wrong apply path"
assert equal ($status.active | length) 2 "status reported the wrong active overlay count"
assert equal ($status.active_frames | length) 2 "status reported the wrong active frame count"
assert ("build" in $status.exports) "status did not report exported build command"
assert equal $status.cleanup_needed true "status did not expose pending cleanup state"
assert equal $status.pending_frame_cleanup false "status incorrectly reported pending frame cleanup inside project"
assert equal $after $before "status changed shell state"
