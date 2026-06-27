# Nushell's `source` and `overlay use/hide` are parser keywords. They cannot
# consume ordinary runtime variables for file paths or overlay names, so this
# integration writes small literal Nushell files and sources those from hooks.
const overlay_source = ($nu.temp-dir | path join $"nu-direnv-overlay-($nu.pid).nu")
const overlay_source_command = $"source '($overlay_source)'"

def --env "__nu-direnv-overlay quote" [value: string] {
  $value | to nuon
}

def "__nu-direnv-overlay log" [event: string, data?: any] {
  let path = ($env.NU_DIRENV_OVERLAY_LOG? | default "")
  if $path == "" {
    return
  }

  mkdir ($path | path dirname)
  {
    time: (date now | into string)
    pid: $nu.pid
    pwd: ($env.PWD? | default null)
    event: $event
    data: ($data | default null)
  } | to nuon | $"($in)\n" | save --append --force $path
}

def --env "__nu-direnv-overlay write-source" [--clear-apply] {
  let apply = if $clear_apply {
    ""
  } else {
    $env.DIRENV_NU_OVERLAY_APPLY? | default ""
  }
  let tracked = ($env.NU_DIRENV_OVERLAY_ACTIVE? | default "" | split row ";" | where $it != "")
  let tracked_exports = ($env.NU_DIRENV_OVERLAY_EXPORTS? | default "" | split row (char us) | where $it != "")
  let active = (overlay list | where name =~ '^nu-direnv-' and active == true | get name)
  let previous = ($tracked ++ $active | uniq)
  let hide_lines = (
    $previous
    | each {|name|
        let quoted = (__nu-direnv-overlay quote $name)
        $"if \(\(overlay list | where name == ($quoted) and active == true | is-not-empty\)\) { overlay hide --keep-env [ PWD ] ($quoted) }"
      }
  )
  let hide_export_lines = (
    $tracked_exports
    | each {|name|
        let quoted = (__nu-direnv-overlay quote $name)
        $"hide ($quoted)"
      }
  )
  let source_start_line = 'if ((which "__nu-direnv-overlay log" | is-not-empty)) { __nu-direnv-overlay log "source-wrapper-start" { active: (overlay list | where name =~ "^nu-direnv-" and active == true), env_active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default null), apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null) } }'
  let source_end_line = 'if ((which "__nu-direnv-overlay log" | is-not-empty)) { __nu-direnv-overlay log "source-wrapper-end" { active: (overlay list | where name =~ "^nu-direnv-" and active == true), env_active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default null), apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null) } }'

  # direnv generates the real apply file while evaluating the allowed .envrc.
  # This per-session wrapper gives Nushell a stable path to source from the
  # pre_prompt string hook, while its contents can change after every direnv run.
  let body = if ($apply != "" and ($apply | path exists)) {
    ($hide_lines ++ $hide_export_lines ++ [$source_start_line $"source ((__nu-direnv-overlay quote $apply))" $source_end_line] | str join (char newline))
  } else {
    # Leaving a directory removes DIRENV_NU_OVERLAY_APPLY. In that case direnv
    # cannot produce an apply file for the old overlays, so Nushell generates
    # a small cleanup script from tracked and currently active overlay names.
    let active_line = '$env.NU_DIRENV_OVERLAY_ACTIVE = ""'
    let exports_line = '$env.NU_DIRENV_OVERLAY_EXPORTS = ""'
    ($hide_lines ++ $hide_export_lines ++ [$source_start_line $active_line $exports_line $source_end_line] | str join (char newline))
  }

  mkdir ($overlay_source | path dirname)
  $body | save --force $overlay_source
  __nu-direnv-overlay log "write-source" {
    source: $overlay_source
    apply: $apply
    apply_exists: ($apply != "" and ($apply | path exists))
    tracked: $tracked
    tracked_exports: $tracked_exports
    active: $active
    previous: $previous
    hide_lines: $hide_lines
    hide_export_lines: $hide_export_lines
    body: $body
  }
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
  __nu-direnv-overlay log "export-start" {
    force: $force
    direnv_dir: ($env.DIRENV_DIR? | default null)
    direnv_apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null)
    env_active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default null)
    overlays: (overlay list | where name =~ '^nu-direnv-')
  }

  if $force {
    __nu-direnv-overlay clear-direnv-state
    __nu-direnv-overlay log "export-force-cleared" {
      direnv_dir: ($env.DIRENV_DIR? | default null)
      direnv_apply: ($env.DIRENV_NU_OVERLAY_APPLY? | default null)
      env_active: ($env.NU_DIRENV_OVERLAY_ACTIVE? | default null)
    }
  }

  mut exported = (direnv export json | complete)
  __nu-direnv-overlay log "direnv-export" {
    exit_code: $exported.exit_code
    stdout_empty: ($exported.stdout | str trim | is-empty)
    stdout_keys: (if ($exported.stdout | str trim | is-empty) { [] } else { $exported.stdout | from json | columns })
    stderr: ($exported.stderr | str trim)
  }
  if $exported.exit_code != 0 {
    print --stderr ($exported.stderr | str trim)
    return
  }

  if ($exported.stdout | str trim | is-empty) {
    if (not $force) and (($env.DIRENV_DIR? | default "") != "") and (not (__nu-direnv-overlay has-active-overlays)) {
      __nu-direnv-overlay clear-direnv-state
      $exported = (direnv export json | complete)
      __nu-direnv-overlay log "direnv-export-after-clear" {
        exit_code: $exported.exit_code
        stdout_empty: ($exported.stdout | str trim | is-empty)
        stdout_keys: (if ($exported.stdout | str trim | is-empty) { [] } else { $exported.stdout | from json | columns })
        stderr: ($exported.stderr | str trim)
      }
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
    __nu-direnv-overlay log "export-end-empty" {
      status: (nu-direnv-overlay status)
      overlays: (overlay list | where name =~ '^nu-direnv-')
    }
    return
  }

  $exported.stdout | from json | load-env
  __nu-direnv-overlay write-source
  __nu-direnv-overlay install-source-hook
  __nu-direnv-overlay log "export-end-loaded" {
    status: (nu-direnv-overlay status)
    overlays: (overlay list | where name =~ '^nu-direnv-')
  }
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
