open $inherited_json | load-env
$env.PATH = ($env.PATH | prepend $direnv_bin_dir)
source $autoload

nu-direnv-overlay reload
nu-direnv-overlay status | get apply
