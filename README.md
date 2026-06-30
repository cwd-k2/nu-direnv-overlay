# nu-direnv-overlay

`nu-direnv-overlay` loads and unloads project-local Nushell overlays from
`.envrc` through direnv.

## Usage

Suppose you have a project like this:

```text
my-project/
├── .envrc
├── flake.nix
└── overlay/
    ├── task.nu
    ├── git.nu
    └── docker.nu
```

Put the Nushell modules you want to expose inside `overlay/`. For example,
`overlay/task.nu` can export project commands:

```nu
export def build [] {
  cargo build
}

export def test [] {
  cargo test
}
```

`overlay/git.nu` can export Git shortcuts:

```nu
export def st [] {
  git status --short
}
```

Then list those overlays from `.envrc`:

```sh
use nu-overlay overlay/task.nu
use nu-overlay overlay/docker.nu
use nu-overlay overlay/git.nu
```

Allow direnv for the project:

```sh
direnv allow
```

Inside the project, `build`, `test`, and `st` are available. After leaving the
directory, the overlays are hidden again.

Globs and explicit overlay names are intentionally not supported. List overlays
one per line instead:

```sh
use nu-overlay overlay/task.nu
use nu-overlay overlay/git.nu
use nu-overlay overlay/docker.nu
```

## How It Works

`nu-direnv-overlay` does not replace direnv's Nushell hook. Keep the normal
direnv hook that runs `direnv export json` and loads the resulting environment;
this project consumes the extra `DIRENV_NU_OVERLAY_APPLY` variable produced by
`.envrc`.

The integration follows direnv's normal shell-hook model:

```text
Nushell direnv hook
  -> direnv export json
  -> .envrc use nu-overlay
  -> /tmp/nu-direnv-overlay.XXXXXXXXXX/apply.nu
  -> DIRENV_NU_OVERLAY_APPLY
  -> Nushell load-env
nu-direnv-overlay sync hook
  -> refreshes direnv env for the current directory
  -> writes a per-session wrapper
nu-direnv-overlay source hook
  -> sources the wrapper after cd and before command resolution
```

direnv still owns `.envrc` evaluation and file watching. The normal Nushell
direnv hook can load env for prompt rendering; `nu-direnv-overlay` installs the
same split sync/source pair in `pre_prompt` and `pre_execution`, plus a PWD
change sync hook that refreshes the wrapper immediately after `cd`. The prompt
hook keeps path completion and project commands in sync; the pre-execution hook
refreshes again before command resolution. The overlay state must be applied
inside the parent shell, because a child direnv process cannot mutate
parent-shell overlays directly.

The `.envrc` function writes a Nushell apply file and exports its path as
`DIRENV_NU_OVERLAY_APPLY`:

```text
/tmp/nu-direnv-overlay.kJ9mQ2xP4a/apply.nu
```

That file is plain Nushell and can be inspected directly:

```nu
# task
overlay use --reload "/abs/path/overlay/task.nu" as "nu-direnv-1000-123456789-111111111"
# git
overlay use --reload "/abs/path/overlay/git.nu" as "nu-direnv-1000-123456789-222222222"
$env.NU_DIRENV_OVERLAY_ACTIVE = "nu-direnv-1000-123456789-111111111;nu-direnv-1000-123456789-222222222"
let nu_direnv_overlay_modules = ["nu-direnv-1000-123456789-111111111" "nu-direnv-1000-123456789-222222222" ]
$env.NU_DIRENV_OVERLAY_EXPORTS = (
  scope modules
  | where {|module| $module.name in $nu_direnv_overlay_modules }
  | each {|module|
      ($module.commands | get name)
      ++ ($module.aliases | get name)
      ++ ($module.externs | get name)
      ++ ($module.constants | get name)
      ++ ($module.submodules | get name)
    }
  | flatten
  | uniq
  | str join (char us)
)
```

Internally, the actual Nushell overlay names are derived from the project path
and each overlay file path, using `nu-direnv-<uid>-<project-checksum>-<file-checksum>`.
This avoids user-managed names and lets cleanup hide only overlays created by
this tool. Exported commands keep their original names; for example,
`overlay/task.nu` can still expose `build`.

The generated `apply.nu` only loads the new overlays and records the exported
definition names. Cleanup is generated in the parent Nushell session as a
per-session wrapper, because only that session can see and mutate the active
interactive overlays:

```nu
if ((overlay list | where name == "nu-direnv-1000-123456789-111111111" and active == true | is-not-empty)) {
  let keep_env = { PROJECT_MARK: "B" }
  let keep_names = [ PROJECT_MARK PWD PROMPT_COMMAND ]
  overlay hide --keep-env [ PWD PROMPT_COMMAND ] "nu-direnv-1000-123456789-111111111"
  for name in ($env | reject --optional FILE_PWD CURRENT_FILE config | columns) {
    if $name not-in $keep_names { hide-env $name --ignore-errors }
  }
  load-env $keep_env
}
hide "build"
hide "project_name"
$env.NU_DIRENV_OVERLAY_ACTIVE = ""
$env.NU_DIRENV_OVERLAY_EXPORTS = ""
$env.NU_DIRENV_OVERLAY_APPLY_LOADED = ""
```

Cleanup snapshots the current post-direnv environment before hiding old
overlays, keeps `PWD` and non-serializable prompt closures during
`overlay hide`, removes names resurrected from the old overlay activation
environment, then restores the snapshot. This prevents old project environment
values from leaking back while moving between projects. Nushell can also leave
exported definitions visible after an overlay becomes inactive, so
`NU_DIRENV_OVERLAY_EXPORTS` tracks exported commands, aliases, externs,
constants, and submodules and hides those names during cleanup.

Cleanup hides exported definitions by name. In normal use those names come from
the project overlay, but if you manually define another command, alias, extern,
constant, or module with the same name in the same interactive scope, cleanup
can hide that manual definition too. Prefer distinct names for ad-hoc shell
definitions when they overlap with project overlay exports.

## Security Model

`nu-direnv-overlay` follows direnv's trust model: only run `direnv allow` in
projects you trust. Files referenced by `use nu-overlay` are loaded into your
interactive Nushell session, and the generated `apply.nu` file is sourced by
Nushell.

The generated apply file is written under a fresh `mktemp -d` directory with
`0700` permissions. The path is passed through `DIRENV_NU_OVERLAY_APPLY`; treat
that variable as trusted output from the allowed `.envrc`.

## Notes on Nushell

Nushell `source`, `overlay use`, `overlay hide`, and `hide` are parser
keywords, so they cannot freely consume ordinary runtime variables as file
paths or names. For that reason, direnv and the Nushell hook generate literal
Nushell files with the paths and names already written into the source code.

The package installs its Nushell integration in
`share/nushell/vendor/autoload`, which is Nushell's vendor/package-manager
autoload location for interactive sessions.

## NixOS

```nix
{
  inputs.nu-direnv-overlay.url = "github:cwd-k2/nu-direnv-overlay";

  outputs = { nixpkgs, nu-direnv-overlay, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        nu-direnv-overlay.nixosModules.default
        { programs.nu-direnv-overlay.enable = true; }
      ];
    };
  };
}
```

This installs `nu-direnv-overlay`, `direnv`, and `nushell`, registers the
direnv stdlib function system-wide, and exposes the Nushell autoload file from
the system profile.

You still need the normal Nushell direnv hook in your Nushell configuration.
This module intentionally does not replace that hook; it adds overlay support on
top of direnv's normal environment and applies overlay state at command time.

## Home Manager

```nix
{
  imports = [ inputs.nu-direnv-overlay.homeManagerModules.default ];
  programs.nu-direnv-overlay.enable = true;
}
```

You still need the normal Nushell direnv hook in your Nushell configuration.

## Profile Install

```sh
nix profile install github:cwd-k2/nu-direnv-overlay
```

Nushell loads files from `share/nushell/vendor/autoload` in Nix profiles. For a
manual Nushell setup, inspect the package paths:

```sh
nu-direnv-overlay paths
```

Then add a literal `source /path/to/nu-direnv-overlay.nu` line to your
`config.nu` or to a file under `$nu.user-autoload-dirs`.

If direnv does not load the package direnv library automatically, add this to
`~/.config/direnv/direnvrc`:

```sh
eval "$(nu-direnv-overlay hook direnv)"
```

## CLI

```sh
nu-direnv-overlay paths
nu-direnv-overlay hook nu
nu-direnv-overlay hook direnv
```
