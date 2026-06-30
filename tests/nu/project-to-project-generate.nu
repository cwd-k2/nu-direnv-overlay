source $autoload
open $inherited_b_json | load-env
source $apply_a
cd $project_b_dir
__nu-direnv-overlay write-source
wrapper-path
