use std/assert

source $autoload

let fake_bin = ($tmpdir | path join "fake-direnv-bin")
mkdir $fake_bin

let fake_direnv = ($fake_bin | path join "direnv")
let fake_path = ($tmpdir | path join "fake-path")
let apply_path = ($tmpdir | path join "fake-apply.nu")
let export_json = {
  PATH: $fake_path
  CUSTOM_PATH: "left:right"
  NEW_ENV: "loaded"
  OLD_ENV: null
  DIRENV_NU_OVERLAY_APPLY: null
} | to json
let export_json_literal = ($export_json | to nuon)

$"#!($nu.current-exe)
def main [first?: string, second?: string] {
  if $first == \"export\" and $second == \"json\" {
    print ($export_json_literal)
    return
  }
  exit 1
}
" | save --force $fake_direnv
chmod +x $fake_direnv

$env.PATH = ($env.PATH | prepend $fake_bin)
$env.OLD_ENV = "old"
$env.DIRENV_NU_OVERLAY_APPLY = $apply_path
$env.NU_DIRENV_OVERLAY_ACTIVE = "keep-active"
$env.NU_DIRENV_OVERLAY_EXPORTS = "keep-exports"
$env.NU_DIRENV_OVERLAY_ENV_NAMES = "keep-env-names"
$env.NU_DIRENV_OVERLAY_ENV_BEFORE = "keep-env-before"
$env.NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES = "keep-env-before-names"
$env.NU_DIRENV_OVERLAY_ENV_AFTER = "keep-env-after"
$env.NU_DIRENV_OVERLAY_APPLY_LOADED = "keep-loaded"
$env.NU_DIRENV_OVERLAY_APPLY_PWD = "keep-pwd"
$env.ENV_CONVERSIONS = {
  CUSTOM_PATH: {
    from_string: {|s| $s | split row ":" }
    to_string: {|v| $v | str join ":" }
  }
}

__nu-direnv-overlay load-direnv-env

assert equal $env.NEW_ENV "loaded" "direnv json value did not load"
assert equal ($env.OLD_ENV? | default null) null "direnv null value did not unload env"
assert equal $env.DIRENV_NU_OVERLAY_APPLY "" "null apply path was not normalized to empty string"
assert equal $env.NU_DIRENV_OVERLAY_ACTIVE "keep-active" "overlay active marker was not restored"
assert equal $env.NU_DIRENV_OVERLAY_EXPORTS "keep-exports" "overlay exports marker was not restored"
assert equal $env.NU_DIRENV_OVERLAY_ENV_NAMES "keep-env-names" "overlay env names marker was not restored"
assert equal $env.NU_DIRENV_OVERLAY_ENV_BEFORE "keep-env-before" "overlay env before marker was not restored"
assert equal $env.NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES "keep-env-before-names" "overlay env before names marker was not restored"
assert equal $env.NU_DIRENV_OVERLAY_ENV_AFTER "keep-env-after" "overlay env after marker was not restored"
assert equal $env.NU_DIRENV_OVERLAY_APPLY_LOADED "keep-loaded" "overlay loaded marker was not restored"
assert equal $env.NU_DIRENV_OVERLAY_APPLY_PWD "keep-pwd" "overlay pwd marker was not restored"
assert equal $env.CUSTOM_PATH [left right] "custom ENV_CONVERSIONS was not applied"
assert (($env.PATH | describe) =~ "list") "PATH was not converted to a list"
assert ($fake_path in $env.PATH) "converted PATH did not include direnv path"
