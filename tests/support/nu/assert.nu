use std/assert

export def wrapper-path [] {
  $nu.cache-dir | path join "nu-direnv-overlay" $"($nu.pid).nu"
}

export def assert-active-overlay-count [expected: int, message: string] {
  assert equal (
    overlay list
    | where name =~ '^nu-direnv-' and active == true
    | length
  ) $expected $message
}

export def assert-no-active-overlays [] {
  assert (
    overlay list
    | where name =~ '^nu-direnv-' and active == true
    | is-empty
  ) "nu-direnv overlay remained active"
}

export def assert-command-hidden [name: string, message: string] {
  assert not (
    scope commands
    | where name == $name
    | is-not-empty
  ) $message
}
