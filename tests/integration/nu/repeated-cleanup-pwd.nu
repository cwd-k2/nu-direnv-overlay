use std/assert

source $apply
mkdir ($tmpdir | path join "elsewhere/deep")
cd ($tmpdir | path join "elsewhere")
source $cleanup
assert equal $env.PWD ($tmpdir | path join "elsewhere") "first cleanup changed PWD"

cd ($tmpdir | path join "elsewhere/deep")
source $cleanup
assert equal $env.PWD ($tmpdir | path join "elsewhere/deep") "second cleanup changed PWD"

source $cleanup
assert equal $env.PWD ($tmpdir | path join "elsewhere/deep") "idempotent cleanup changed PWD"
