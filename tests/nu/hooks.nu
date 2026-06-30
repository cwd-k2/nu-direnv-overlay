use std/assert

source $autoload

$env.config.hooks.env_change = { PWD: [{|before, after| "existing" }] }
let wrapper = (wrapper-path)
let sq = (char -i 39)
$env.config.hooks.pre_execution = [
  "existing pre-exec"
  "__nu-direnv-overlay sync"
  $"source ($sq)($wrapper)($sq)"
]
mkdir ($wrapper | path dirname)
"error make { msg: \"stale wrapper was sourced\" }" | save --force $wrapper
$env.config.hooks.pre_prompt = [
  "existing prompt"
  "__nu-direnv-overlay sync"
  $"source ($sq)($wrapper)($sq)"
]

__nu-direnv-overlay install-hooks
__nu-direnv-overlay install-hooks

let pre_exec_hooks = ($env.config.hooks.pre_execution | last 2)
let prompt_hooks = ($env.config.hooks.pre_prompt | last 2)
let pwd_hook = ($env.config.hooks.env_change.PWD | last)

assert ("existing pre-exec" in $env.config.hooks.pre_execution) "unrelated pre-execution hook was removed"
assert ("existing prompt" in $env.config.hooks.pre_prompt) "unrelated prompt hook was removed"
assert equal $pre_exec_hooks.0 "__nu-direnv-overlay sync" "pre-execution sync hook was not installed before source hook"
assert ($pre_exec_hooks.1 | str starts-with "source ") "pre-execution source hook was not installed after sync hook"
assert equal (($env.config.hooks.pre_execution | where $it == $pre_exec_hooks.0 | length)) 1 "pre-execution sync hook installation was not idempotent"
assert equal (($env.config.hooks.pre_execution | where $it == $pre_exec_hooks.1 | length)) 1 "pre-execution source hook installation was not idempotent"
assert (($env.config.hooks.env_change.PWD.0 | describe) =~ "closure") "unrelated PWD env_change hook was changed"
assert equal $pwd_hook "__nu-direnv-overlay sync" "PWD env_change sync hook was not installed"

let pwd_string_hooks = ($env.config.hooks.env_change.PWD | where {|hook| ($hook | describe) == "string" })
assert equal (($pwd_string_hooks | where $it == "__nu-direnv-overlay sync" | length)) 1 "PWD env_change sync hook installation was not idempotent"
assert equal $prompt_hooks.0 "__nu-direnv-overlay sync" "prompt sync hook was not installed before source hook"
assert ($prompt_hooks.1 | str starts-with "source ") "prompt source hook was not installed after sync hook"
assert equal (($env.config.hooks.pre_prompt | where $it == $prompt_hooks.0 | length)) 1 "prompt sync hook installation was not idempotent"
assert equal (($env.config.hooks.pre_prompt | where $it == $prompt_hooks.1 | length)) 1 "prompt source hook installation was not idempotent"
assert ($wrapper | path exists) "pre-execution source wrapper was not created before hook installation"
assert equal (open $wrapper) "" "stale pre-execution source wrapper was not reset on install"
