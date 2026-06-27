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

The integration follows direnv's normal shell-hook model:

```text
Nushell PWD hook
  -> direnv export json
  -> .envrc use nu-overlay
  -> /tmp/nu-direnv-overlay.XXXXXXXXXX/apply.nu
  -> DIRENV_NU_OVERLAY_APPLY
  -> Nushell load-env
  -> Nushell source apply.nu
```

direnv still owns `.envrc` evaluation and file watching. Nushell only applies
the resulting state inside the parent shell, because a child `direnv` process
cannot mutate parent-shell overlays directly.

The `.envrc` function writes a Nushell apply file and exports its path as
`DIRENV_NU_OVERLAY_APPLY`:

```text
/tmp/nu-direnv-overlay.kJ9mQ2xP4a/apply.nu
```

That file is plain Nushell and can be inspected directly:

```nu
if ((overlay list | where name == "nu-direnv-1000-123456789-111111111" and active == true | is-not-empty)) { overlay hide "nu-direnv-1000-123456789-111111111" }
# task
overlay use --reload "/abs/path/overlay/task.nu" as "nu-direnv-1000-123456789-111111111"
# git
overlay use --reload "/abs/path/overlay/git.nu" as "nu-direnv-1000-123456789-222222222"
$env.NU_DIRENV_OVERLAY_ACTIVE = "nu-direnv-1000-123456789-111111111;nu-direnv-1000-123456789-222222222"
```

Internally, the actual Nushell overlay names are derived from the project path
and each overlay file path, using `nu-direnv-<uid>-<project-checksum>-<file-checksum>`.
This avoids user-managed names and lets cleanup hide only overlays created by
this tool. Exported commands keep their original names; for example,
`overlay/task.nu` can still expose `build`.

## Security Model

`nu-direnv-overlay` follows direnv's trust model: only run `direnv allow` in
projects you trust. Files referenced by `use nu-overlay` are loaded into your
interactive Nushell session, and the generated `apply.nu` file is sourced by
Nushell.

The generated apply file is written under a fresh `mktemp -d` directory with
`0700` permissions. The path is passed through `DIRENV_NU_OVERLAY_APPLY`; treat
that variable as trusted output from the allowed `.envrc`.

## Notes on Nushell

Nushell `source` and `overlay use` are parser keywords, so they cannot freely
consume ordinary runtime variables as file paths or overlay names. For that
reason, direnv generates a literal `apply.nu` file, and the Nushell hook sources
that file through a per-session wrapper.

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

## Home Manager

```nix
{
  imports = [ inputs.nu-direnv-overlay.homeManagerModules.default ];
  programs.nu-direnv-overlay.enable = true;
}
```

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
