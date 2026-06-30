use std/assert

source $autoload
$env.PATH = ($env.PATH | prepend $direnv_bin_dir)
$env.LAST_EXIT_CODE = 37

__nu-direnv-overlay sync

assert equal $env.LAST_EXIT_CODE 37 "sync changed LAST_EXIT_CODE outside direnv"

open $inherited_json | load-env
cd $project_dir
__nu-direnv-overlay sync
let wrapper = (wrapper-path)
let body = (open $wrapper)

assert ($body | str contains '$env.__NU_DIRENV_OVERLAY_LAST_EXIT_CODE = 37') "wrapper did not capture LAST_EXIT_CODE"
assert ($body | str contains '$env.LAST_EXIT_CODE = $env.__NU_DIRENV_OVERLAY_LAST_EXIT_CODE') "wrapper did not restore LAST_EXIT_CODE"
assert ($body | str contains 'source ') "wrapper did not exercise apply source path"

$wrapper
