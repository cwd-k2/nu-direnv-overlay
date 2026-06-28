# Nushell's `source` and `overlay use/hide` are parser keywords. They cannot
# consume ordinary runtime variables for file paths or overlay names, so this
# integration writes small literal Nushell files and sources those from hooks.
#
# Responsibility boundary:
# - The normal Nushell direnv hook owns `direnv export json` and `load-env`.
# - This file only applies the extra Nushell overlay state exposed through
#   DIRENV_NU_OVERLAY_APPLY.
#
# This split is intentional. Calling direnv here would race with the user's
# existing direnv hook and can consume DIRENV_DIFF in the wrong order.

# Stable per-session wrapper path. Hook strings are installed once, while the
# file contents are rewritten whenever the prompt is about to render.
const overlay_source = ($nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu")

# First pre_prompt hook: rewrite overlay_source from the current env.
const overlay_sync_command = "__nu-direnv-overlay prompt-sync"

# Second pre_prompt hook: source overlay_source in the interactive scope.
const overlay_source_command = $"source '($overlay_source)'"

def --env "__nu-direnv-overlay quote" [value: string] {
  # Generated wrapper files contain literal Nushell code, not runtime variables.
  # NUON string syntax is the safest way to preserve spaces, quotes, and newlines.
  $value | to nuon
}

def "__nu-direnv-overlay active-names" [] {
  # Keep both sources:
  # - NU_DIRENV_OVERLAY_ACTIVE is the last apply file's tracked set.
  # - `overlay list` catches active overlays if env tracking was cleared first.
  let tracked = ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "")
  let active = (overlay list | where name =~ '^nu-direnv-' and active == true | get name)
  $tracked ++ $active | uniq
}

def "__nu-direnv-overlay exported-names" [] {
  # Nushell can leave exported commands/aliases visible after `overlay hide`.
  # The generated apply file records exactly which names the project overlay
  # exported, but a normal direnv unload can remove that env var before this
  # prompt hook runs. Fall back to the still-loaded internal module metadata so
  # cleanup does not leave commands callable without their direnv environment.
  let tracked = ($env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != "")
  let scoped = (
    scope modules
    | where {|module| $module.name =~ '^nu-direnv-' }
    | each {|module|
        (
          ($module.commands | get name)
          ++ ($module.aliases | get name)
          ++ ($module.externs | get name)
          ++ ($module.constants | get name)
          ++ ($module.submodules | get name)
        )
      }
    | flatten
  )
  $tracked ++ $scoped | uniq
}

def "__nu-direnv-overlay hide-overlay-line" [name: string] {
  let quoted = (__nu-direnv-overlay quote $name)
  # `overlay hide` restores the environment that existed when the overlay was
  # activated, except for names listed in --keep-env. Project overlays are loaded
  # after direnv has entered a dev shell, so a plain hide can resurrect Nix env
  # after direnv has unloaded it. Preserve the current env in a temporary env var,
  # hide the overlay while keeping PWD and that temporary var, remove any env
  # names resurrected by `overlay hide`, then load the saved env back. Do not
  # load automatic/special values: Nushell rejects PWD, FILE_PWD, and
  # CURRENT_FILE, and loading `config` can disturb completions.
  $"if \(\(overlay list | where name == ($quoted) and active == true | is-not-empty\)\) { $env.__NU_DIRENV_OVERLAY_KEEP_ENV = \($env | reject --optional PWD FILE_PWD CURRENT_FILE config __NU_DIRENV_OVERLAY_KEEP_ENV\); let __nu_direnv_overlay_keep_names = \($env.__NU_DIRENV_OVERLAY_KEEP_ENV | columns\); overlay hide --keep-env [ PWD __NU_DIRENV_OVERLAY_KEEP_ENV ] ($quoted); let __nu_direnv_overlay_restore_names = \($env | reject --optional PWD FILE_PWD CURRENT_FILE config __NU_DIRENV_OVERLAY_KEEP_ENV | columns | where {|name| $name not-in $__nu_direnv_overlay_keep_names }\); for name in $__nu_direnv_overlay_restore_names { hide-env $name --ignore-errors }; load-env $env.__NU_DIRENV_OVERLAY_KEEP_ENV; hide-env __NU_DIRENV_OVERLAY_KEEP_ENV --ignore-errors }"
}

def "__nu-direnv-overlay hide-export-line" [name: string] {
  # Some exported definitions remain callable after an overlay is hidden.
  # The apply file records exactly what the project exported, so cleanup hides
  # only those names instead of scanning the whole command table.
  $"hide ((__nu-direnv-overlay quote $name))"
}

def "__nu-direnv-overlay cleanup-lines" [] {
  # Ordering matters. Hide overlays first so their env layer is removed, then
  # hide exported definitions that Nushell may otherwise leave in scope.
  let hide_overlays = (__nu-direnv-overlay active-names | each {|name| __nu-direnv-overlay hide-overlay-line $name })
  let hide_exports = (__nu-direnv-overlay exported-names | each {|name| __nu-direnv-overlay hide-export-line $name })
  $hide_overlays ++ $hide_exports
}

def "__nu-direnv-overlay apply-path" [--cleanup-only] {
  # For cleanup-only calls, deliberately ignore any stale apply path that may
  # still be present in env. Re-sourcing a stale apply would re-enable overlays
  # while leaving a project.
  if $cleanup_only {
    ""
  } else {
    $env.DIRENV_NU_OVERLAY_APPLY? | default ""
  }
}

def "__nu-direnv-overlay apply-wrapper-lines" [apply: string] {
  # Every apply starts with cleanup. direnv can rebuild the apply file when
  # .envrc changes, and repeated `overlay use --reload` without hiding first can
  # leave old exported definitions visible.
  (__nu-direnv-overlay cleanup-lines) ++ [$"source ((__nu-direnv-overlay quote $apply))"]
}

def "__nu-direnv-overlay cleanup-wrapper-lines" [] {
  # When direnv unloads a directory, there is no project apply file anymore.
  # The wrapper still needs to remove active overlays and clear tracking env.
  (__nu-direnv-overlay cleanup-lines) ++ [
    '$env.NU_DIRENV_OVERLAY_ACTIVE = ""'
    '$env.NU_DIRENV_OVERLAY_EXPORTS = ""'
    '$env.NU_DIRENV_OVERLAY_APPLY_LOADED = ""'
  ]
}

def "__nu-direnv-overlay apply-already-loaded" [apply: string] {
  # pre_prompt runs on every Enter. Re-hiding exported commands and then sourcing
  # the exact same overlay can leave Nushell with commands hidden while their
  # module is active. If the same apply file is already loaded and the active
  # nu-direnv overlay set exactly matches what that apply file tracks, the
  # correct wrapper is a no-op.
  if ($apply == "" or (($env.NU_DIRENV_OVERLAY_APPLY_LOADED? | default "") != $apply)) {
    return false
  }

  let tracked = ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "" | uniq | sort)
  if ($tracked | is-empty) {
    return false
  }

  let active = (overlay list | where name =~ '^nu-direnv-' and active == true | get name | uniq | sort)
  $tracked == $active
}

def --env "__nu-direnv-overlay write-source" [--cleanup-only] {
  let apply = (__nu-direnv-overlay apply-path --cleanup-only=$cleanup_only)

  # direnv generates the real apply file while evaluating the allowed .envrc.
  # This per-session wrapper gives Nushell a stable path to source from the
  # pre_prompt string hook, while its contents can change after every direnv run.
  let body = if (__nu-direnv-overlay apply-already-loaded $apply) {
    []
  } else if ($apply != "" and ($apply | path exists)) {
    __nu-direnv-overlay apply-wrapper-lines $apply
  } else {
    # Leaving a directory removes DIRENV_NU_OVERLAY_APPLY. In that case direnv
    # cannot produce an apply file for the old overlays.
    __nu-direnv-overlay cleanup-wrapper-lines
  }

  mkdir ($overlay_source | path dirname)
  # The pre_prompt hook sources this stable path. Its contents are rewritten
  # after direnv updates env, which avoids putting dynamic paths in hook strings.
  $body | str join (char newline) | save --force $overlay_source
}

def --env "__nu-direnv-overlay install-prompt-hooks" [] {
  # String hooks are parsed as if typed at the prompt. The sync hook updates the
  # wrapper after other PWD hooks have had a chance to load direnv's env diff;
  # the source hook then applies overlay parser keywords in the interactive
  # scope, where exported definitions become visible.
  let hooks = (
    $env.config.hooks.pre_prompt? | default []
    # Remove our previous strings before appending. Autoload files can be sourced
    # more than once in long-lived shells, and duplicate pre_prompt hooks would
    # repeatedly hide/source overlays on every Enter.
    | where {|hook| $hook != $overlay_sync_command and $hook != $overlay_source_command }
  )
  # prompt-sync must run before source. sync writes the wrapper for the current
  # direnv state; source then evaluates parser keywords (`source`, `overlay hide`)
  # in the real interactive scope.
  $env.config.hooks.pre_prompt = ($hooks | append $overlay_sync_command | append $overlay_source_command)
}

def --env "__nu-direnv-overlay sync-overlays" [] {
  # This tool intentionally does not call `direnv export json` or `load-env`.
  # The normal Nushell direnv hook owns env changes. We only consume
  # DIRENV_NU_OVERLAY_APPLY after that hook has updated the parent shell env.
  __nu-direnv-overlay write-source
  __nu-direnv-overlay install-prompt-hooks
}

def --env "__nu-direnv-overlay prompt-sync" [] {
  # Runs on every prompt. It is cheap enough to rewrite the small wrapper file,
  # and doing it every time avoids depending on PWD hook ordering.
  __nu-direnv-overlay sync-overlays
}

export def --env "nu-direnv-overlay status" [] {
  # Debug surface for users. Keep this cheap and side-effect free so it is safe
  # to run while diagnosing prompt hook behavior.
  {
    source: $overlay_source
    apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null)
    active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "")
    exports: ($env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != "")
  }
}

export def --env "nu-direnv-overlay reload" [] {
  # Manual resync for troubleshooting. It does not re-run direnv; it only
  # rewrites the wrapper from the current env and reinstalls prompt hooks.
  __nu-direnv-overlay sync-overlays
}

if $nu.is-interactive {
  # Official Nushell hooks only run in interactive sessions. That is exactly
  # where overlays matter, so non-interactive `nu -c` and scripts stay inert.
  #
  # Do not install a PWD hook here. PWD hook ordering differs by user config, and
  # inherited marker env vars can make installation unreliable in child shells.
  # The prompt hook observes the env after the normal direnv hook has run.
  __nu-direnv-overlay install-prompt-hooks
}
