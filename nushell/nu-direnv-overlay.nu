# Nushell's `source` and `overlay use/hide` are parser keywords. They cannot
# consume ordinary runtime variables for file paths or overlay names, so this
# integration writes small literal Nushell files and sources those from hooks.
#
# Responsibility boundary:
# - The normal Nushell direnv hook owns prompt-time `direnv export json` and
#   `load-env`.
# - This file applies the extra Nushell overlay state exposed through
#   DIRENV_NU_OVERLAY_APPLY, and refreshes env in split hooks so stale prompt
#   string sources cannot break the user's next command or path completion.
#
# This split is intentional. Prompt rendering can still be handled by the
# user's normal direnv hook; directory changes refresh the wrapper, then prompt
# and command hooks source it before completion or command resolution.

# Stable per-session wrapper path. Hook strings are installed once, while the
# file contents are rewritten before each command. Keep it out of /tmp so
# cleanup jobs do not remove it from long-lived shells.
const overlay_source = ($nu.cache-dir | path join "nu-direnv-overlay" $"($nu.pid).nu")

# Keep sync and source as separate adjacent hooks. Nushell resolves `source`
# inputs early inside one string hook, so a single `sync; source ...` string can
# source the wrapper contents from before sync rewrote them. Split hooks have
# been verified to let the source hook see the freshly written file before the
# user's command resolves or prompt-time completion reads the scope.
const overlay_sync_command = "__nu-direnv-overlay sync"
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
  # Hide only names recorded by the generated apply file. `scope modules` is too
  # broad here: in some Nushell versions a loaded module can report inherited
  # commands, and hiding those can remove builtins such as `print`.
  $env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != "" | uniq
}

def "__nu-direnv-overlay current-env-record" [] {
  # Capture the current post-direnv environment at wrapper generation time.
  # Generated cleanup uses this record after `overlay hide` to remove names
  # resurrected from the overlay activation environment, then restore captured
  # values. Same-named variables from different projects are therefore compared
  # by the current snapshot, not by the overlay being hidden.
  #
  # Only keep values that can be serialized into generated source and restored
  # with `load-env`. Prompt closures such as starship's PROMPT_COMMAND belong to
  # the user's config and cannot be represented safely in NUON.
  $env
  | reject --optional PWD FILE_PWD CURRENT_FILE config __NU_DIRENV_OVERLAY_KEEP_ENV __NU_DIRENV_OVERLAY_KEEP_NAMES __NU_DIRENV_OVERLAY_PRESERVE_NAMES NU_DIRENV_OVERLAY_ACTIVE NU_DIRENV_OVERLAY_EXPORTS NU_DIRENV_OVERLAY_APPLY_LOADED NU_DIRENV_OVERLAY_APPLY_PWD
  | transpose name value
  | where {|row| ($row.value | describe) !~ "closure" }
  | transpose --header-row --as-record
}

def "__nu-direnv-overlay current-env-literal" [] {
  __nu-direnv-overlay current-env-record
  | to nuon
}

def "__nu-direnv-overlay current-env-names" [] {
  # Names allowed to exist after cleanup. This includes non-serializable values,
  # such as prompt closures, even though those values are absent from the
  # `load-env` snapshot.
  $env
  | reject --optional FILE_PWD CURRENT_FILE config
  | columns
}

def "__nu-direnv-overlay current-env-names-literal" [] {
  __nu-direnv-overlay current-env-names
  | to nuon
}

def "__nu-direnv-overlay preserve-env-names" [] {
  # Names whose current values must survive `overlay hide` itself. PWD is always
  # controlled by the current shell directory. Closure values cannot be
  # serialized, so they are preserved in place instead of restored via load-env.
  let closure_names = (
    $env
    | reject --optional FILE_PWD CURRENT_FILE config
    | transpose name value
    | where {|row| ($row.value | describe) =~ "closure" }
    | get name
  )
  [PWD] ++ $closure_names | uniq
}

def "__nu-direnv-overlay preserve-env-names-literal" [] {
  __nu-direnv-overlay preserve-env-names
  | to nuon
}

def "__nu-direnv-overlay hide-overlay-line" [name: string, keep_env: string, keep_names: string, preserve_names: string] {
  let quoted = (__nu-direnv-overlay quote $name)
  # `overlay hide` restores the environment that existed when the overlay was
  # activated, except for names listed in --keep-env. Project overlays are loaded
  # after direnv has entered a dev shell, so a plain hide can resurrect Nix env
  # after direnv has unloaded it. Generated cleanup embeds the current
  # post-direnv env record and allowed name list as literals. `overlay hide`
  # keeps only PWD and currently-present non-serializable closure values. Cleanup
  # then removes names outside the allowed list and restores serializable values
  # from the literal record. Automatic/special values are excluded because
  # Nushell rejects FILE_PWD/CURRENT_FILE and loading `config` can disturb
  # completions.
  $"if \(\(overlay list | where name == ($quoted) and active == true | is-not-empty\)\) { let __nu_direnv_overlay_preserve_names = \(($preserve_names) | where {|name| $name in \($env | columns\) }\); overlay hide --keep-env $__nu_direnv_overlay_preserve_names ($quoted); for name in \($env | reject --optional FILE_PWD CURRENT_FILE config | columns\) { if $name not-in ($keep_names) { hide-env $name --ignore-errors } }; load-env ($keep_env) }"
}

def "__nu-direnv-overlay hide-export-line" [name: string] {
  # Some exported definitions remain callable after an overlay is hidden.
  # The apply file records exactly what the project exported, so cleanup hides
  # only those names instead of scanning the whole command table.
  $"hide ((__nu-direnv-overlay quote $name))"
}

def "__nu-direnv-overlay cleanup-lines" [--hide-overlays] {
  # Ordering matters. Hide overlays first so their env layer is removed, then
  # hide exported definitions that Nushell may otherwise leave in scope.
  let keep_env = (__nu-direnv-overlay current-env-literal)
  let keep_names = (__nu-direnv-overlay current-env-names-literal)
  let preserve_names = (__nu-direnv-overlay preserve-env-names-literal)
  let hide_overlays = if $hide_overlays {
    __nu-direnv-overlay active-names | each {|name| __nu-direnv-overlay hide-overlay-line $name $keep_env $keep_names $preserve_names }
  } else {
    []
  }
  let hide_exports = (__nu-direnv-overlay exported-names | each {|name| __nu-direnv-overlay hide-export-line $name })
  $hide_overlays ++ $hide_exports
}

def --env "__nu-direnv-overlay load-direnv-env" [] {
  if (which direnv | is-empty) {
    return
  }

  let overlay_state = {
    NU_DIRENV_OVERLAY_ACTIVE: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default null)
    NU_DIRENV_OVERLAY_EXPORTS: ($env.NU_DIRENV_OVERLAY_EXPORTS? | default null)
    NU_DIRENV_OVERLAY_APPLY_LOADED: ($env.NU_DIRENV_OVERLAY_APPLY_LOADED? | default null)
    NU_DIRENV_OVERLAY_APPLY_PWD: ($env.NU_DIRENV_OVERLAY_APPLY_PWD? | default null)
  }

  try {
    let exported = (direnv export json | complete)
    let env_delta = ($exported.stdout | from json --strict | default {})
    let env_rows = ($env_delta | transpose name value)

    for name in ($env_rows | where value == null | get name) {
      if $name == "DIRENV_NU_OVERLAY_APPLY" {
        $env.DIRENV_NU_OVERLAY_APPLY = ""
      } else {
        hide-env $name --ignore-errors
      }
    }

    let env_values = ($env_rows | where value != null)
    if ($env_values | is-not-empty) {
      $env_values
      | transpose --header-row --as-record
      | items {|key, value|
          let value = do (
            {
              "PATH": {
                from_string: {|s| $s | split row (char esep) | path expand --no-symlink }
                to_string: {|v| $v | path expand --no-symlink | str join (char esep) }
              }
            }
            | merge ($env.ENV_CONVERSIONS? | default {})
            | get ([[value, optional, insensitive]; [$key, true, true] [from_string, true, false]] | into cell-path)
            | if ($in | is-empty) { {|x| $x} } else { $in }
          ) $value
          return [ $key $value ]
        }
      | into record
      | load-env
    }
    $overlay_state
    | transpose name value
    | where value != null
    | transpose --header-row --as-record
    | load-env
  } catch {
    null
  }
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
  let quoted = (__nu-direnv-overlay quote $apply)
  let quoted_pwd = (__nu-direnv-overlay quote (pwd))
  let keep_env = (__nu-direnv-overlay current-env-literal)
  (__nu-direnv-overlay cleanup-lines --hide-overlays) ++ [
    $"source ($quoted)"
    $"$env.NU_DIRENV_OVERLAY_APPLY_PWD = ($quoted_pwd)"
    $"load-env ($keep_env)"
  ]
}

def "__nu-direnv-overlay cleanup-wrapper-lines" [] {
  # When direnv unloads a directory, there is no project apply file anymore.
  # Prompt-time `overlay hide` can leave Nushell's file completer with a stale
  # permanent cwd. Hide exported definitions and env immediately, then defer
  # hiding active overlay frames until the next project apply can do a full
  # cleanup before loading fresh overlays.
  (__nu-direnv-overlay cleanup-lines --hide-overlays=false) ++ [
    'hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors'
    '$env.DIRENV_NU_OVERLAY_APPLY = ""'
    '$env.NU_DIRENV_OVERLAY_ACTIVE = ""'
    '$env.NU_DIRENV_OVERLAY_EXPORTS = ""'
    '$env.NU_DIRENV_OVERLAY_APPLY_LOADED = ""'
    '$env.NU_DIRENV_OVERLAY_APPLY_PWD = ""'
  ]
}

def "__nu-direnv-overlay cleanup-needed" [] {
  let has_exports = (__nu-direnv-overlay exported-names | is-not-empty)
  let has_apply = (($env.DIRENV_NU_OVERLAY_APPLY? | default "") != "")
  let has_active_marker = (($env.NU_DIRENV_OVERLAY_ACTIVE? | default "") != "")
  let has_exports_marker = (($env.NU_DIRENV_OVERLAY_EXPORTS? | default "") != "")
  let has_loaded_marker = (($env.NU_DIRENV_OVERLAY_APPLY_LOADED? | default "") != "")
  let has_pwd_marker = (($env.NU_DIRENV_OVERLAY_APPLY_PWD? | default "") != "")

  $has_exports or $has_apply or $has_active_marker or $has_exports_marker or $has_loaded_marker or $has_pwd_marker
}

def "__nu-direnv-overlay ensure-source" [--reset] {
  mkdir ($overlay_source | path dirname)
  if ($reset or not ($overlay_source | path exists)) {
    "" | save --force $overlay_source
  }
}

def "__nu-direnv-overlay apply-already-loaded" [apply: string] {
  # Sync runs before prompt rendering and before every command. Re-hiding
  # exported commands and then sourcing the exact same overlay can leave Nushell
  # with commands hidden while their module is active. If the same apply file is
  # already loaded and the active nu-direnv overlay set exactly matches what
  # that apply file tracks, the correct wrapper is a no-op.
  if ($apply == "" or (($env.NU_DIRENV_OVERLAY_APPLY_LOADED? | default "") != $apply)) {
    return false
  }
  if (($env.NU_DIRENV_OVERLAY_APPLY_PWD? | default "") != (pwd)) {
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
  mkdir ($overlay_source | path dirname)
  "" | save --force $overlay_source

  let body = if (__nu-direnv-overlay apply-already-loaded $apply) {
    []
  } else if ($apply != "" and ($apply | path exists)) {
    __nu-direnv-overlay apply-wrapper-lines $apply
  } else if not (__nu-direnv-overlay cleanup-needed) {
    []
  } else {
    # Leaving a directory removes DIRENV_NU_OVERLAY_APPLY. In that case direnv
    # cannot produce an apply file for the old overlays.
    __nu-direnv-overlay cleanup-wrapper-lines
  }

  # The source hook reads this stable path after the adjacent sync hook has
  # rewritten it for the current directory.
  $body | str join (char newline) | save --force $overlay_source
}

def "__nu-direnv-overlay merge-hook-pair" [existing_hooks: list] {
  let hooks = (
    $existing_hooks
    | where {|hook| $hook != $overlay_sync_command and $hook != $overlay_source_command }
  )

  $hooks
  | append $overlay_sync_command
  | append $overlay_source_command
}

def "__nu-direnv-overlay merge-sync-hook" [existing_hooks: list] {
  $existing_hooks
  | where {|hook| $hook != $overlay_sync_command }
  | append $overlay_sync_command
}

def --env "__nu-direnv-overlay install-hooks" [--preserve-source] {
  __nu-direnv-overlay ensure-source --reset=(not $preserve_source)

  $env.config.hooks.pre_execution = (
    __nu-direnv-overlay merge-hook-pair ($env.config?.hooks?.pre_execution? | default [])
  )
  $env.config.hooks.env_change.PWD = (
    __nu-direnv-overlay merge-sync-hook ($env.config?.hooks?.env_change?.PWD? | default [])
  )
  $env.config.hooks.pre_prompt = (
    __nu-direnv-overlay merge-hook-pair ($env.config?.hooks?.pre_prompt? | default [])
  )
}

def --env "__nu-direnv-overlay sync" [] {
  __nu-direnv-overlay load-direnv-env
  __nu-direnv-overlay write-source
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
  # Manual resync for troubleshooting. It refreshes direnv env for the current
  # directory, rewrites the wrapper, and reinstalls hooks.
  __nu-direnv-overlay sync
  __nu-direnv-overlay install-hooks --preserve-source
}

if $nu.is-interactive {
  # Official Nushell hooks only run in interactive sessions. That is exactly
  # where overlays matter, so non-interactive `nu -c` and scripts stay inert.
  #
  __nu-direnv-overlay install-hooks
  __nu-direnv-overlay sync
}
