use std/assert

source $autoload
open $inherited_b_json | load-env
source $apply_a
cd $project_b_dir
source $wrapper

assert equal $env.PWD $project_b_dir "project-to-project wrapper changed PWD"
assert equal (build) "built-b" "project B build command did not replace project A build command"
assert equal (b_only) "b-only" "project B unique command did not load"
assert-command-hidden "st" "project A command leaked into project B"
assert equal ($env.PROJECT_MARK? | default "") "B" "project B env was not preserved during project-to-project cleanup"
assert equal (nu-direnv-overlay status | get active | length) 1 "unexpected active overlay count after project-to-project cleanup"
