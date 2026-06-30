# Test Layout

Tests are grouped by the boundary they exercise.

## `unit/nu`

Pure Nushell checks for local behavior inside the autoload module. These tests
should avoid real project fixtures unless the function under test needs a
minimal shell state record.

Use this layer for:

- hook list merging
- plan record shape
- wrapper rendering decisions
- side-effect-free helper behavior

## `integration`

Cross-boundary tests that involve generated apply files, direnv JSON, project
fixtures, or sourcing wrappers in a non-interactive Nushell process.

Use this layer for:

- `.envrc` and `use nu-overlay` behavior
- generated apply file shape
- wrapper apply/cleanup transitions
- project-to-project and project-to-unmanaged state changes

## `e2e`

Interactive-shell tests. These use `nu --testbin=nu_repl` and PTY/Expect where
the behavior depends on real prompt hooks, command resolution, or Reedline
completion.

Use this layer only when non-interactive Nushell cannot observe the behavior.

## `support`

Shared harness, fixtures, and Nushell assertions. Support files should expose
test vocabulary, not product behavior.
