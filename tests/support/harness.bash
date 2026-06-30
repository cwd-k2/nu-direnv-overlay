# shellcheck shell=bash

autoload="$PKG/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
direnv_lib="$PKG/share/direnv/lib/nu-overlay.sh"
direnv_bin_dir=$(dirname "$DIRENV")
generated_tests_dir="$TMPDIR/generated-tests"

nu_quote() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '"%s"' "$value"
}

run_nu() {
  "$NU" --no-config-file "$@"
}

init_test_env() {
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$TMPDIR/config"
  export XDG_DATA_HOME="$TMPDIR/data"
  export XDG_CACHE_HOME="$TMPDIR/cache"

  mkdir -p "$HOME" "$XDG_CONFIG_HOME/direnv" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$generated_tests_dir"
  printf 'source %q\n' "$direnv_lib" >"$XDG_CONFIG_HOME/direnv/direnvrc"
}

assert_installed_files() {
  test -x "$PKG/bin/nu-direnv-overlay"
  test -f "$direnv_lib"
  test -f "$autoload"
}

assert_direnv_api() {
  "$DIRENV" stdlib >"$TMPDIR/stdlib.sh"
  . "$direnv_lib"
  type use_nu-overlay >/dev/null
}

assert_nu_autoload() {
  run_nu --commands 'source "'"$autoload"'"; nu-direnv-overlay status | ignore'
}

assert_helper_hook_output_quoting() {
  local fake_pkg="$TMPDIR/pkg with \"quote"
  local fake_nu="$fake_pkg/share/nushell/vendor/autoload/nu-direnv-overlay.nu"
  local fake_direnv="$fake_pkg/share/direnv/lib/nu-overlay.sh"

  mkdir -p "$(dirname "$fake_nu")" "$(dirname "$fake_direnv")"
  printf 'export def "nu-direnv-overlay status" [] { null }\n' >"$fake_nu"
  printf 'use_nu-overlay() { :; }\n' >"$fake_direnv"

  NU_DIRENV_OVERLAY_PKG="$fake_pkg" "$PKG/bin/nu-direnv-overlay" hook nu >"$TMPDIR/hook.nu"
  run_nu --commands "$(cat "$TMPDIR/hook.nu"); nu-direnv-overlay status | ignore"

  NU_DIRENV_OVERLAY_PKG="$fake_pkg" "$PKG/bin/nu-direnv-overlay" hook direnv >"$TMPDIR/direnvrc"
  (
    . "$TMPDIR/direnvrc"
    type use_nu-overlay >/dev/null
  )
}

write_nu_test() {
  local test_layer=$1
  local case_name=$2
  local out=$3
  shift 3

  {
    printf 'const tmpdir = %s\n' "$(nu_quote "$TMPDIR")"
    printf 'const autoload = %s\n' "$(nu_quote "$autoload")"
    printf 'const direnv_bin_dir = %s\n' "$(nu_quote "$direnv_bin_dir")"
    printf 'const project_dir = %s\n' "$(nu_quote "$TMPDIR/project")"
    printf 'const project_b_dir = %s\n' "$(nu_quote "$TMPDIR/project-b")"
    printf 'const nested_child_dir = %s\n' "$(nu_quote "$TMPDIR/nested/child")"
    printf 'const assert_file = %s\n' "$(nu_quote "$test_dir/support/nu/assert.nu")"
    printf 'source $assert_file\n'

    while [ "$#" -gt 0 ]; do
      local key=$1
      local value=$2
      shift 2
      printf 'const %s = %s\n' "$key" "$(nu_quote "$value")"
    done

    printf '\n'
    printf 'source %s\n' "$(nu_quote "$test_dir/$test_layer/nu/$case_name.nu")"
  } >"$out"
}

run_nu_test() {
  local test_layer=$1
  local case_name=$2
  local generated="$generated_tests_dir/$test_layer-$case_name.nu"
  shift 2

  write_nu_test "$test_layer" "$case_name" "$generated" "$@"
  run_nu "$generated"
}

run_nu_test_stdout() {
  local test_layer=$1
  local case_name=$2
  local generated="$generated_tests_dir/$test_layer-$case_name.nu"
  shift 2

  write_nu_test "$test_layer" "$case_name" "$generated" "$@"
  run_nu "$generated"
}

direnv_json_for() {
  local project_dir=$1
  local out=$2

  (
    cd "$project_dir"
    "$DIRENV" export json >"$out"
  )
}

apply_path_for() {
  local project_dir=$1

  (
    cd "$project_dir"
    run_nu --commands "$DIRENV export json | from json | get DIRENV_NU_OVERLAY_APPLY"
  )
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  local message=$3

  if ! grep -q "$pattern" "$file"; then
    echo "$message" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_file_not_contains() {
  local file=$1
  local pattern=$2
  local message=$3

  if grep -q "$pattern" "$file"; then
    echo "$message" >&2
    cat "$file" >&2
    exit 1
  fi
}
