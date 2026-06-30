use std/assert

source $autoload
open $inherited_json | load-env
source $apply
cd $tmpdir
jump root

assert equal $env.PWD $project_dir "overlay command did not cd to project root"
__nu-direnv-overlay write-source

let wrapper = (wrapper-path)
assert equal ((ls $wrapper | get size.0 | into int)) 0 "pre-execution sync after command cd was not a no-op"
assert equal $env.PWD $project_dir "pre-execution sync after command cd changed PWD"
