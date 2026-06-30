use std/assert

source $autoload
open $inherited_json | load-env
source $apply
cd $tmpdir
jump root
open $inherited_again_json | load-env
source $wrapper

assert equal $env.PWD $project_dir "changed apply after command cd changed PWD"
assert equal (build) "built" "build command did not load"
assert equal (st) "status" "st command did not load"
