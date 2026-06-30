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
# and command hooks source it before completion or command resolution. Prompt
# cleanup hides exported definitions immediately. Active overlay frames are
# hidden only when loading a new project overlay, because prompt-time or
# command-time `overlay hide` before a prompt can leave Reedline path completion
# with a stale cwd.

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
  # Cleanup must only touch overlays tracked by the last generated apply file.
  # `overlay list` is still useful for diagnostics, but using it as ownership
  # input can hide user/third-party overlays or bake stale frames into wrappers.
  $env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "" | uniq
}

def "__nu-direnv-overlay exported-names" [] {
  # Nushell can leave exported commands/aliases visible after `overlay hide`.
  # Hide only names recorded by the generated apply file. `scope modules` is too
  # broad here: in some Nushell versions a loaded module can report inherited
  # commands, and hiding those can remove builtins such as `print`.
  $env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != "" | uniq
}

def "__nu-direnv-overlay overlay-env-names" [] {
  $env.NU_DIRENV_OVERLAY_ENV_NAMES? | default "" | split row (char us) | where $it != "" | uniq
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
  | reject --optional PWD FILE_PWD CURRENT_FILE config LAST_EXIT_CODE __NU_DIRENV_OVERLAY_KEEP_ENV __NU_DIRENV_OVERLAY_KEEP_NAMES __NU_DIRENV_OVERLAY_PRESERVE_NAMES __NU_DIRENV_OVERLAY_LAST_EXIT_CODE __NU_DIRENV_OVERLAY_PWD NU_DIRENV_OVERLAY_ACTIVE NU_DIRENV_OVERLAY_EXPORTS NU_DIRENV_OVERLAY_ENV_NAMES NU_DIRENV_OVERLAY_ENV_BEFORE NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES NU_DIRENV_OVERLAY_ENV_AFTER NU_DIRENV_OVERLAY_APPLY_LOADED NU_DIRENV_OVERLAY_APPLY_PWD
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
  $"if \(\(overlay list | where {|overlay| $overlay.name == ($quoted) and $overlay.active == true } | is-not-empty\)\) { $env.__NU_DIRENV_OVERLAY_PWD = \(pwd\); let __nu_direnv_overlay_preserve_names = \(\(($preserve_names) ++ [\"__NU_DIRENV_OVERLAY_LAST_EXIT_CODE\", \"__NU_DIRENV_OVERLAY_PWD\"]\) | where {|name| $name in \($env | columns\) }\); overlay hide --keep-custom --keep-env $__nu_direnv_overlay_preserve_names ($quoted); cd $env.__NU_DIRENV_OVERLAY_PWD; hide-env __NU_DIRENV_OVERLAY_PWD --ignore-errors; for name in \($env | reject --optional FILE_PWD CURRENT_FILE config | columns\) { if $name not-in \(($keep_names) ++ [\"__NU_DIRENV_OVERLAY_LAST_EXIT_CODE\", \"__NU_DIRENV_OVERLAY_PWD\"]\) { hide-env $name --ignore-errors } }; load-env ($keep_env) }"
}

def "__nu-direnv-overlay hide-export-line" [name: string] {
  # Some exported definitions remain callable after an overlay is hidden.
  # The apply file records exactly what the project exported, so cleanup hides
  # only those names instead of scanning the whole command table.
  $"hide ((__nu-direnv-overlay quote $name))"
}

def "__nu-direnv-overlay restore-overlay-env-line" [names: string, before_env: string, before_names: string, after_env: string] {
  $"let __nu_direnv_overlay_env_before = ($before_env); let __nu_direnv_overlay_env_before_names = ($before_names); let __nu_direnv_overlay_env_after = ($after_env); for name in ($names) { let applied_value = \($__nu_direnv_overlay_env_after | get --optional $name\); let current_value = \($env | get --optional $name\); if $current_value == $applied_value { if $name in $__nu_direnv_overlay_env_before_names { load-env { $name: \($__nu_direnv_overlay_env_before | get $name\) } } else { hide-env $name --ignore-errors } } }"
}

def "__nu-direnv-overlay cleanup-plan" [--hide-overlays] {
  # Ordering matters. Hide overlays first so their env layer is removed, then
  # hide exported definitions that Nushell may otherwise leave in scope. Finally
  # restore environment values changed by overlay `export-env` blocks.
  let keep_env = (__nu-direnv-overlay current-env-literal)
  let keep_names = (__nu-direnv-overlay current-env-names-literal)
  let preserve_names = (__nu-direnv-overlay preserve-env-names-literal)
  let overlay_env_names = (__nu-direnv-overlay overlay-env-names)
  let overlay_env_before = ($env.NU_DIRENV_OVERLAY_ENV_BEFORE? | default "")
  let overlay_env_before_names = ($env.NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES? | default "")
  let overlay_env_after = ($env.NU_DIRENV_OVERLAY_ENV_AFTER? | default "")
  let hide_overlays = if $hide_overlays {
    __nu-direnv-overlay active-names | each {|name|
      {
        type: hide_overlay
        name: $name
        keep_env: $keep_env
        keep_names: $keep_names
        preserve_names: $preserve_names
      }
    }
  } else {
    []
  }
  let hide_exports = (__nu-direnv-overlay exported-names | each {|name| { type: hide_export, name: $name } })
  let restore_overlay_env = if ($overlay_env_names | is-empty) { [] } else { [
    {
      type: restore_overlay_env
      names: ($overlay_env_names | to nuon)
      before_env: (if $overlay_env_before == "" { "{}" } else { $overlay_env_before })
      before_names: (if $overlay_env_before_names == "" { "[]" } else { $overlay_env_before_names })
      after_env: (if $overlay_env_after == "" { "{}" } else { $overlay_env_after })
    }
  ] }
  $hide_overlays ++ $hide_exports ++ $restore_overlay_env
}

def --env "__nu-direnv-overlay load-direnv-env" [] {
  if (which direnv | is-empty) {
    return
  }

  let overlay_state = {
    NU_DIRENV_OVERLAY_ACTIVE: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default null)
    NU_DIRENV_OVERLAY_EXPORTS: ($env.NU_DIRENV_OVERLAY_EXPORTS? | default null)
    NU_DIRENV_OVERLAY_ENV_NAMES: ($env.NU_DIRENV_OVERLAY_ENV_NAMES? | default null)
    NU_DIRENV_OVERLAY_ENV_BEFORE: ($env.NU_DIRENV_OVERLAY_ENV_BEFORE? | default null)
    NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES: ($env.NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES? | default null)
    NU_DIRENV_OVERLAY_ENV_AFTER: ($env.NU_DIRENV_OVERLAY_ENV_AFTER? | default null)
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

def "__nu-direnv-overlay apply-plan" [apply: string] {
  # Every apply starts with cleanup. direnv can rebuild the apply file when
  # .envrc changes, and repeated `overlay use --reload` without hiding first can
  # leave old exported definitions visible.
  (__nu-direnv-overlay cleanup-plan --hide-overlays) ++ [
    { type: source_apply, path: $apply }
    { type: mark_apply_pwd, pwd: (pwd) }
  ]
}

def "__nu-direnv-overlay cleanup-plan-only" [] {
  # When direnv unloads a directory, there is no project apply file anymore.
  # Prompt-time cleanup must not hide active overlay frames because that can
  # leave Reedline completion with a stale cwd. Deferred frames are hidden by
  # the next project apply, which runs cleanup before loading fresh overlays.
  # Keep the active marker so that later apply can still identify the deferred
  # frames after cleanup-only has hidden exported definitions.
  (__nu-direnv-overlay cleanup-plan --hide-overlays=false) ++ [
    { type: line, source: 'hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors' }
    { type: line, source: '$env.DIRENV_NU_OVERLAY_APPLY = ""' }
    { type: line, source: '$env.NU_DIRENV_OVERLAY_EXPORTS = ""' }
    { type: line, source: '$env.NU_DIRENV_OVERLAY_ENV_NAMES = ""' }
    { type: line, source: '$env.NU_DIRENV_OVERLAY_ENV_BEFORE = ""' }
    { type: line, source: '$env.NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES = ""' }
    { type: line, source: '$env.NU_DIRENV_OVERLAY_ENV_AFTER = ""' }
    { type: line, source: '$env.NU_DIRENV_OVERLAY_APPLY_LOADED = ""' }
    { type: line, source: '$env.NU_DIRENV_OVERLAY_APPLY_PWD = ""' }
  ]
}

def "__nu-direnv-overlay cleanup-needed" [] {
  let has_exports = (__nu-direnv-overlay exported-names | is-not-empty)
  let has_active_overlay = (overlay list | where name =~ '^nu-direnv-' and active == true | is-not-empty)
  let has_apply = (($env.DIRENV_NU_OVERLAY_APPLY? | default "") != "")
  let has_active_marker = (($env.NU_DIRENV_OVERLAY_ACTIVE? | default "") != "")
  let has_exports_marker = (($env.NU_DIRENV_OVERLAY_EXPORTS? | default "") != "")
  let has_env_marker = (($env.NU_DIRENV_OVERLAY_ENV_NAMES? | default "") != "")
  let has_env_before_marker = (($env.NU_DIRENV_OVERLAY_ENV_BEFORE? | default "") != "")
  let has_env_before_names_marker = (($env.NU_DIRENV_OVERLAY_ENV_BEFORE_NAMES? | default "") != "")
  let has_env_after_marker = (($env.NU_DIRENV_OVERLAY_ENV_AFTER? | default "") != "")
  let has_loaded_marker = (($env.NU_DIRENV_OVERLAY_APPLY_LOADED? | default "") != "")
  let has_pwd_marker = (($env.NU_DIRENV_OVERLAY_APPLY_PWD? | default "") != "")

  $has_exports or $has_active_overlay or $has_apply or $has_active_marker or $has_exports_marker or $has_env_marker or $has_env_before_marker or $has_env_before_names_marker or $has_env_after_marker or $has_loaded_marker or $has_pwd_marker
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

def "__nu-direnv-overlay wrapper-plan" [--cleanup-only] {
  let apply = (__nu-direnv-overlay apply-path --cleanup-only=$cleanup_only)

  if (__nu-direnv-overlay apply-already-loaded $apply) {
    { type: noop, apply: $apply, actions: [] }
  } else if ($apply != "" and ($apply | path exists)) {
    { type: apply, apply: $apply, actions: (__nu-direnv-overlay apply-plan $apply) }
  } else if not (__nu-direnv-overlay cleanup-needed) {
    { type: noop, apply: $apply, actions: [] }
  } else {
    # Leaving a directory removes DIRENV_NU_OVERLAY_APPLY. In that case direnv
    # cannot produce an apply file for the old overlays.
    { type: cleanup, apply: $apply, actions: (__nu-direnv-overlay cleanup-plan-only) }
  }
}

def "__nu-direnv-overlay render-action" [action: record] {
  match $action.type {
    "hide_overlay" => {
      __nu-direnv-overlay hide-overlay-line $action.name $action.keep_env $action.keep_names $action.preserve_names
    }
    "hide_export" => {
      __nu-direnv-overlay hide-export-line $action.name
    }
    "restore_overlay_env" => {
      __nu-direnv-overlay restore-overlay-env-line $action.names $action.before_env $action.before_names $action.after_env
    }
    "source_apply" => {
      $"source ((__nu-direnv-overlay quote $action.path))"
    }
    "mark_apply_pwd" => {
      $"$env.NU_DIRENV_OVERLAY_APPLY_PWD = ((__nu-direnv-overlay quote $action.pwd))"
    }
    "load_env" => {
      $"load-env ($action.env)"
    }
    "line" => {
      $action.source
    }
  }
}

def "__nu-direnv-overlay render-wrapper-plan" [plan: record] {
  $plan.actions | each {|action| __nu-direnv-overlay render-action $action }
}

def --env "__nu-direnv-overlay write-source" [--cleanup-only] {
  let last_exit_code = ($env.LAST_EXIT_CODE? | default null)
  mkdir ($overlay_source | path dirname)
  "" | save --force $overlay_source

  let plan = (__nu-direnv-overlay wrapper-plan --cleanup-only=$cleanup_only)
  let body = (__nu-direnv-overlay render-wrapper-plan $plan)

  let wrapped_body = if ($body | is-empty) {
    []
  } else {
    [
      $"$env.__NU_DIRENV_OVERLAY_LAST_EXIT_CODE = (($last_exit_code | to nuon))"
    ] ++ $body ++ [
      'if $env.__NU_DIRENV_OVERLAY_LAST_EXIT_CODE == null { hide-env LAST_EXIT_CODE --ignore-errors } else { $env.LAST_EXIT_CODE = $env.__NU_DIRENV_OVERLAY_LAST_EXIT_CODE }'
      'hide-env __NU_DIRENV_OVERLAY_LAST_EXIT_CODE --ignore-errors'
    ]
  }

  # The source hook reads this stable path after the adjacent sync hook has
  # rewritten it for the current directory.
  $wrapped_body | str join (char newline) | save --force $overlay_source
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
  let last_exit_code = ($env.LAST_EXIT_CODE? | default null)
  __nu-direnv-overlay load-direnv-env
  if $last_exit_code == null {
    hide-env LAST_EXIT_CODE --ignore-errors
  } else {
    $env.LAST_EXIT_CODE = $last_exit_code
  }
  __nu-direnv-overlay write-source
  if $last_exit_code == null {
    hide-env LAST_EXIT_CODE --ignore-errors
  } else {
    $env.LAST_EXIT_CODE = $last_exit_code
  }
}

def "__nu-direnv-overlay active-frame-names" [] {
  overlay list | where name =~ '^nu-direnv-' and active == true | get name
}

export def --env "nu-direnv-overlay status" [] {
  # Debug surface for users. Keep this cheap and side-effect free so it is safe
  # to run while diagnosing prompt hook behavior.
  let active_frames = (__nu-direnv-overlay active-frame-names)
  {
    source: $overlay_source
    apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null)
    active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "")
    active_frames: $active_frames
    exports: ($env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != "")
    cleanup_needed: (__nu-direnv-overlay cleanup-needed)
    pending_frame_cleanup: (($env.DIRENV_NU_OVERLAY_APPLY? | default "") == "" and ($active_frames | is-not-empty))
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
