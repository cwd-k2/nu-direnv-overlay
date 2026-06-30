use std/assert

source $autoload
open $inherited_json | load-env
source $apply
__nu-direnv-overlay write-source

let wrapper = (wrapper-path)
assert ($wrapper | path exists) "same-project wrapper was not created"
assert equal ((ls $wrapper | get size.0 | into int)) 0 "same-project wrapper was not empty"
$wrapper
