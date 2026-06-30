use std/assert

source $autoload
$env.PATH = ($env.PATH | prepend $direnv_bin_dir)
$env.LAST_EXIT_CODE = 37

__nu-direnv-overlay sync

assert equal $env.LAST_EXIT_CODE 37 "sync changed LAST_EXIT_CODE outside direnv"

open $inherited_json | load-env
cd $project_dir
let plan = (__nu-direnv-overlay wrapper-plan)
assert equal $plan.type apply "sync fixture did not choose apply plan"
assert equal (
  $plan.actions | where type == source_apply | length
) 1 "sync fixture did not plan to source apply path"

__nu-direnv-overlay sync
wrapper-path
