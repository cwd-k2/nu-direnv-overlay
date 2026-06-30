source $autoload
open $inherited_json | load-env
source $apply
cd $tmpdir
jump root
open $inherited_again_json | load-env
__nu-direnv-overlay write-source
wrapper-path
