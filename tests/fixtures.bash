# shellcheck shell=bash

create_standard_fixtures() {
  mkdir -p "$TMPDIR/project/overlay"
  cat >"$TMPDIR/project/.envrc" <<'EOF'
export PROJECT_ROOT="$PWD"
use nu-overlay overlay/task.nu
use nu-overlay overlay/git.nu
EOF
  cat >"$TMPDIR/project/overlay/task.nu" <<'EOF'
export const project_name = "project"
export module nested { export def hi [] { "hi" } }
export def build [] { "built" }
export def --env "jump root" [] { cd $env.PROJECT_ROOT }
EOF
  cat >"$TMPDIR/project/overlay/git.nu" <<'EOF'
export def st [] { "status" }
EOF

  mkdir -p "$TMPDIR/project-b/overlay"
  cat >"$TMPDIR/project-b/.envrc" <<'EOF'
export PROJECT_MARK=B
use nu-overlay overlay/task.nu
EOF
  cat >"$TMPDIR/project-b/overlay/task.nu" <<'EOF'
export def build [] { "built-b" }
export def b_only [] { "b-only" }
EOF

  mkdir -p "$TMPDIR/nested/child/overlay" "$TMPDIR/nested/overlay"
  cat >"$TMPDIR/nested/.envrc" <<'EOF'
export NESTED_PARENT_ROOT="$PWD"
use nu-overlay overlay/parent.nu
EOF
  cat >"$TMPDIR/nested/overlay/parent.nu" <<'EOF'
export def nested_parent [] { "parent" }
EOF
  cat >"$TMPDIR/nested/child/.envrc" <<'EOF'
source_up
export NESTED_CHILD_ROOT="$PWD"
use nu-overlay overlay/child.nu
EOF
  cat >"$TMPDIR/nested/child/overlay/child.nu" <<'EOF'
export def nested_child [] { "child" }
EOF
}

allow_standard_fixtures() {
  (
    cd "$TMPDIR/project"
    "$DIRENV" allow . >/dev/null
  )
  (
    cd "$TMPDIR/project-b"
    "$DIRENV" allow . >/dev/null
  )
  (
    cd "$TMPDIR/nested"
    "$DIRENV" allow . >/dev/null
  )
  (
    cd "$TMPDIR/nested/child"
    "$DIRENV" allow . >/dev/null
  )
}
