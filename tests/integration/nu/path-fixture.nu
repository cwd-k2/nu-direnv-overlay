use std/assert

open $path_fixture_json | load-env
source $apply

assert equal (path_fixture_hi) "path-ok" "overlay command from path fixture did not load"
assert equal ($env.PATH_FIXTURE_ROOT? | default "") $path_fixture_dir "path fixture env did not load"
assert-active-overlay-count 1 "unexpected active overlay count for path fixture"
