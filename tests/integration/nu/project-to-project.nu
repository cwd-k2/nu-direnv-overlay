use std/assert

source $autoload
open $inherited_b_json | load-env
source $apply_a
$env.PROMPT_COMMAND = {|| "prompt" }
cd $project_b_dir
source $wrapper

assert equal $env.PWD $project_b_dir "project-to-project wrapper changed PWD"
assert equal (do $env.PROMPT_COMMAND) "prompt" "project-to-project cleanup removed prompt closure"
assert equal (build) "built-b" "project B build command did not replace project A build command"
assert equal (b_only) "b-only" "project B unique command did not load"
assert-command-hidden "st" "project A command leaked into project B"
assert equal ($env.PROJECT_ROOT? | default "") "" "project A env leaked into project B"
assert equal ($env.PROJECT_MARK? | default "") "B" "project B env was not preserved during project-to-project cleanup"
let status = (nu-direnv-overlay status)
assert equal ($status.active | length) 1 "unexpected active overlay marker count after project-to-project cleanup"
assert equal ($status.active_frames | length) 1 "unexpected active overlay frame count after project-to-project cleanup"
assert equal ($status.active | sort) ($status.active_frames | sort) "active overlay markers did not match active frames"
