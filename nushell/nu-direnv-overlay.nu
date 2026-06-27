# Nushell's `source` and `overlay use/hide` are parser keywords. They cannot
# consume ordinary runtime variables for file paths or overlay names, so this
# integration writes small literal Nushell files and sources those from hooks.
const overlay_source = ($nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu")
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
  $env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != ""
}

def "__nu-direnv-overlay cleanup-lines" [] {
  let hide_overlays = (
    __nu-direnv-overlay active-names
    | each {|name|
        let quoted = (__nu-direnv-overlay quote $name)
        $"if \(\(overlay list | where name == ($quoted) and active == true | is-not-empty\)\) { overlay hide --keep-env [ PWD ] ($quoted) }"
      }
  )

  let hide_exports = (
    __nu-direnv-overlay exported-names
    | each {|name| $"hide ((__nu-direnv-overlay quote $name))" }
  )

  $hide_overlays ++ $hide_exports
}

def --env "__nu-direnv-overlay write-source" [--clear-apply] {
  let apply = if $clear_apply { "" } else { $env.DIRENV_NU_OVERLAY_APPLY? | default "" }
  let cleanup_lines = (__nu-direnv-overlay cleanup-lines)

  # direnv generates the real apply file while evaluating the allowed .envrc.
  # This per-session wrapper gives Nushell a stable path to source from the
  # pre_prompt string hook, while its contents can change after every direnv run.
  let body = if ($apply != "" and ($apply | path exists)) {
    $cleanup_lines ++ [$"source ((__nu-direnv-overlay quote $apply))"]
  } else {
    # Leaving a directory removes DIRENV_NU_OVERLAY_APPLY. In that case direnv
    # cannot produce an apply file for the old overlays.
    $cleanup_lines ++ [
      '$env.NU_DIRENV_OVERLAY_ACTIVE = ""'
      '$env.NU_DIRENV_OVERLAY_EXPORTS = ""'
    ]
  }

  mkdir ($overlay_source | path dirname)
  $body | str join (char newline) | save --force $overlay_source
}

def --env "__nu-direnv-overlay install-source-hook" [] {
  let hooks = ($env.config.hooks.pre_prompt? | default [])
  if not ($hooks | any {|hook| $hook == $overlay_source_command }) {
    # String hooks are parsed as if typed at the prompt, which lets overlay
    # definitions escape hook closure scope and become visible interactively.
    $env.config.hooks.pre_prompt = ($hooks | append $overlay_source_command)
  }
}

def "__nu-direnv-overlay has-active-overlays" [] {
  let active = ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "")
  if ($active | is-empty) {
    false
  } else {
    $active | all {|name|
      overlay list | where name == $name and active == true | is-not-empty
    }
  }
}

def --env "__nu-direnv-overlay clear-direnv-state" [] {
  hide-env DIRENV_DIFF --ignore-errors
  hide-env DIRENV_DIR --ignore-errors
  hide-env DIRENV_FILE --ignore-errors
  hide-env DIRENV_WATCHES --ignore-errors
  hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
}

def --env "__nu-direnv-overlay export-direnv" [--force] {
  # Match the direnv shell hook model: ask direnv for the environment diff, load
  # that diff into this shell, then apply the Nushell-only overlay changes.
  if $force {
    __nu-direnv-overlay clear-direnv-state
  }

  mut exported = (direnv export json | complete)
  if $exported.exit_code != 0 {
    print --stderr ($exported.stderr | str trim)
    return
  }

  if ($exported.stdout | str trim | is-empty) {
    if (not $force) and (($env.DIRENV_DIR? | default "") != "") and (not (__nu-direnv-overlay has-active-overlays)) {
      __nu-direnv-overlay clear-direnv-state
      $exported = (direnv export json | complete)
      if $exported.exit_code != 0 {
        print --stderr ($exported.stderr | str trim)
        return
      }
    }
  }

  if ($exported.stdout | str trim | is-empty) {
    hide-env DIRENV_NU_OVERLAY_APPLY --ignore-errors
    __nu-direnv-overlay write-source --clear-apply
    __nu-direnv-overlay install-source-hook
    return
  }

  $exported.stdout | from json | load-env
  __nu-direnv-overlay write-source
  __nu-direnv-overlay install-source-hook
}

def --env "__nu-direnv-overlay on-pwd" [before?: string, after?: string] {
  __nu-direnv-overlay export-direnv
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
  __nu-direnv-overlay export-direnv --force
}

if $nu.is-interactive {
  # Official Nushell hooks only run in interactive sessions. That is exactly
  # where overlays matter, so non-interactive `nu -c` and scripts stay inert.
  let env_change = ($env.config.hooks.env_change? | default {})
  let pwd_hooks = ($env_change.PWD? | default [])
  let hook = {|before, after| __nu-direnv-overlay on-pwd $before $after }

  $env.config.hooks.env_change = ($env_change | upsert PWD ($pwd_hooks | append $hook))
  __nu-direnv-overlay export-direnv
}
