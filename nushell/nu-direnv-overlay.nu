# Nushell's `source` and `overlay use/hide` are parser keywords. They cannot
# consume ordinary runtime variables for file paths or overlay names, so this
# integration writes small literal Nushell files and sources those from hooks.
const overlay_source = ($nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu")
const overlay_sync_command = "__nu-direnv-overlay prompt-sync"
const overlay_source_command = $"source '($overlay_source)'"

def --env "__nu-direnv-overlay quote" [value: string] {
  $value | to nuon
}

def "__nu-direnv-overlay active-names" [] {
  let tracked = ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "")
  let active = (overlay list | where name =~ '^nu-direnv-' and active == true | get name)
  $tracked ++ $active | uniq
}

def "__nu-direnv-overlay exported-names" [] {
  # Nushell can leave exported commands/aliases visible after `overlay hide`.
  # The generated apply file records exactly which names the project overlay
  # exported, so cleanup can hide only those definitions.
  $env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != ""
}

def "__nu-direnv-overlay hide-overlay-line" [name: string] {
  let quoted = (__nu-direnv-overlay quote $name)
  $"if \(\(overlay list | where name == ($quoted) and active == true | is-not-empty\)\) { overlay hide --keep-env [ PWD ] ($quoted) }"
}

def "__nu-direnv-overlay hide-export-line" [name: string] {
  $"hide ((__nu-direnv-overlay quote $name))"
}

def "__nu-direnv-overlay cleanup-lines" [] {
  let hide_overlays = (__nu-direnv-overlay active-names | each {|name| __nu-direnv-overlay hide-overlay-line $name })
  let hide_exports = (__nu-direnv-overlay exported-names | each {|name| __nu-direnv-overlay hide-export-line $name })
  $hide_overlays ++ $hide_exports
}

def "__nu-direnv-overlay apply-path" [--cleanup-only] {
  if $cleanup_only {
    ""
  } else {
    $env.DIRENV_NU_OVERLAY_APPLY? | default ""
  }
}

def "__nu-direnv-overlay apply-wrapper-lines" [apply: string] {
  (__nu-direnv-overlay cleanup-lines) ++ [$"source ((__nu-direnv-overlay quote $apply))"]
}

def "__nu-direnv-overlay cleanup-wrapper-lines" [] {
  (__nu-direnv-overlay cleanup-lines) ++ [
    '$env.NU_DIRENV_OVERLAY_ACTIVE = ""'
    '$env.NU_DIRENV_OVERLAY_EXPORTS = ""'
  ]
}

def --env "__nu-direnv-overlay write-source" [--cleanup-only] {
  let apply = (__nu-direnv-overlay apply-path --cleanup-only=$cleanup_only)

  # direnv generates the real apply file while evaluating the allowed .envrc.
  # This per-session wrapper gives Nushell a stable path to source from the
  # pre_prompt string hook, while its contents can change after every direnv run.
  let body = if ($apply != "" and ($apply | path exists)) {
    __nu-direnv-overlay apply-wrapper-lines $apply
  } else {
    # Leaving a directory removes DIRENV_NU_OVERLAY_APPLY. In that case direnv
    # cannot produce an apply file for the old overlays.
    __nu-direnv-overlay cleanup-wrapper-lines
  }

  mkdir ($overlay_source | path dirname)
  $body | str join (char newline) | save --force $overlay_source
}

def --env "__nu-direnv-overlay install-prompt-hooks" [] {
  # String hooks are parsed as if typed at the prompt. The sync hook updates the
  # wrapper after other PWD hooks have had a chance to load direnv's env diff;
  # the source hook then applies overlay parser keywords in the interactive
  # scope, where exported definitions become visible.
  let hooks = (
    $env.config.hooks.pre_prompt? | default []
    | where {|hook| $hook != $overlay_sync_command and $hook != $overlay_source_command }
  )
  $env.config.hooks.pre_prompt = ($hooks | append $overlay_sync_command | append $overlay_source_command)
}

def --env "__nu-direnv-overlay sync-overlays" [] {
  __nu-direnv-overlay write-source
  __nu-direnv-overlay install-prompt-hooks
}

def --env "__nu-direnv-overlay prompt-sync" [] {
  __nu-direnv-overlay sync-overlays
}

export def --env "nu-direnv-overlay status" [] {
  {
    source: $overlay_source
    apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null)
    active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "")
    exports: ($env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != "")
  }
}

export def --env "nu-direnv-overlay reload" [] {
  __nu-direnv-overlay sync-overlays
}

if $nu.is-interactive {
  # Official Nushell hooks only run in interactive sessions. That is exactly
  # where overlays matter, so non-interactive `nu -c` and scripts stay inert.
  __nu-direnv-overlay install-prompt-hooks
}
