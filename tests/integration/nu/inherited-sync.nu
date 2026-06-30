open $inherited_json | load-env
$env.PATH = ($env.PATH | prepend $direnv_bin_dir)
source $autoload

__nu-direnv-overlay sync
nu-direnv-overlay status | get apply
