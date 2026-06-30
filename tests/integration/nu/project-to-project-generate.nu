source $autoload
open $inherited_b_json | load-env
source $apply_a
$env.PROMPT_COMMAND = {|| "prompt" }
cd $project_b_dir
__nu-direnv-overlay write-source
wrapper-path
