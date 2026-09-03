# Scripts

## `bootstrap-nix.sh`

Main machine bootstrap. It handles:

- OS detection
- Nix installation and pinned profile provisioning
- Ubuntu 24.04/26.04 host integration
- CLI, .NET, Python, Rust, fonts, and Ghostty through Nix
- Node.js installation through `fnm`
- npm-native tools using the configured npm registry
- cleanup of legacy .NET bootstrap artifacts, with opt-in directory removal
- shell, prompt, Ghostty, and JJ config generation
- Git configuration

Run:

```bash
./bootstrap-nix.sh
```

`bootstrap-dev-shell.sh` and `bootstrap-wsl-nix.sh` delegate to this command
for compatibility.

## `configure-copilot-sandbox.sh`

Merges the global Copilot CLI MXC policy into `~/.copilot/settings.json`
without replacing unrelated settings. The policy:

- enables command sandboxing and disables per-command bypass
- allows the working directory, developer tools, outbound traffic, and
  localhost development services
- grants read-only access to the Nix store and Copilot package cache
- grants read-write access to the Playwright browser cache
- injects Git and GitHub authentication into sandboxed commands
- sandboxes LSP servers
- denies access to `/mnt/c`

Run:

```bash
./configure-copilot-sandbox.sh
```

The script is idempotent and preserves existing filesystem paths. Set
`COPILOT_SETTINGS_FILE` to configure a different settings file.

## `configure-zellij.sh`

Writes a managed `~/.config/zellij/config.kdl`.

Main characteristics:

- vim-like pane and tab movement
- clipboard integration using the first available helper:
  - `clip.exe`
  - `pbcopy`
  - `wl-copy`
  - `xclip`
  - `xsel`
- high-contrast GitHub light/dark themes with automatic terminal appearance detection
- GitHub light theme fallback for terminals that do not report their appearance
- opinionated keymap

Run:

```bash
./configure-zellij.sh
```

## `update-nix.sh`

Updates the `nixpkgs` revision pinned by `nix/flake.lock`, checks and builds the
updated flake, upgrades the installed development profile generation, and
activates the matching Home Manager generation.
It activates the installed Nix profile automatically when `nix` is not already
on `PATH`.

Run:

```bash
./update-nix.sh
```

After it succeeds, review and commit the `nix/flake.lock` change.

## `test-nix.sh`

Runs the isolated-home bootstrap checks, verifies `nixfmt` formatting, evaluates
the flake for every supported system, and builds the current machine's tool
environment locally.

Run:

```bash
./test-nix.sh
```

## `launch-wt-wsl.ps1`

Launches Windows Terminal directly into WSL.

Parameters:

- `-Distro`: optional WSL distro name
- `-WorkingDirectory`: WSL path such as `~`, `/home/...`, or `/mnt/c/...`
- `-Shell`: shell to exec inside WSL, default `zsh`
- `-WtPath`: override path to `wt.exe`
- `-NewWindow`: open a new Windows Terminal window

Run from Windows PowerShell:

```powershell
.\launch-wt-wsl.ps1
```

Examples:

```powershell
.\launch-wt-wsl.ps1 -Distro Ubuntu
.\launch-wt-wsl.ps1 -Distro Ubuntu -WorkingDirectory /home/your-user/src
.\launch-wt-wsl.ps1 -NewWindow
```

## `nix-wt`

Creates or reopens a rootless OverlayFS view of a Git repository and runs a
given command inside it through the bootstrap repository's Nix dev shell.

By default, the launcher uses the repository containing the current directory.
An explicit repository path can be passed with `-C`. Each overlay receives a
persistent writable layer under a repository-specific directory in
`${XDG_STATE_HOME:-~/.local/state}/nix-wt/` and an immutable base checkout under
the sibling `<repository>.worktrees/` directory. Git repositories receive a
branch named `user/keegancaruso/<overlay-name>`. Colocated Jujutsu repositories
receive a bookmark with that name.

Run for an explicit repository:

```zsh
./nix-wt issue-123 -C /path/to/repository -- zsh
```

Run another command:

```zsh
./nix-wt experiment -- zsh
```

Run `./bootstrap-nix.sh` once on a new WSL installation before using the
launcher. `nix-wt` explicitly activates the resulting Nix profile for its own
process; normal Zsh sessions do not activate Nix through the bootstrap template.

This creates:

```text
Lower:   <repository>.worktrees/nix-wt-issue-123
Overlay: ~/.local/state/nix-wt/<repo-name>-<repo-id>/issue-123/merged
State:   ~/.local/state/nix-wt/<repo-name>-<repo-id>/issue-123
Branch or bookmark: user/keegancaruso/issue-123
```

The overlay is unmounted when the command exits, while its writable layer
remains available for another `nix-wt` session with the same repository and
overlay name. The lower checkout remains fixed at the commit from which the
overlay was created, so the source checkout can advance without changing an
active or persisted overlay. The launcher records the repository, lower
directory, base commit, and VCS mode to validate reopened state.

For colocated Jujutsu repositories, the lower checkout is an independent local
clone initialized with its own `.git` and `.jj` metadata. This is used instead
of a linked Git worktree because Jujutsu does not support colocated
initialization inside linked Git worktrees. Git objects are copied so later
maintenance or garbage collection in the source checkout cannot invalidate a
persisted overlay. Refs, indexes, and Jujutsu operations also remain isolated.

State created by older versions is migrated automatically on first reopen.
The launcher reconstructs an immutable Git lower checkout at the recorded base
commit, preserves the existing writable layer, and records the new lower
metadata before mounting it. New Jujutsu-aware overlays still use isolated
Jujutsu metadata; migrated legacy overlays remain in their original Git mode.
If the recorded base commit is no longer available, recover it from the remote
or another clone before reopening the overlay. A legacy writable layer that
contains `.jj` metadata is refused before migration because partial Jujutsu
state cannot be reconstructed safely; reopen that overlay with the older
launcher and push its work first.

The command runs in a collectible systemd user scope named
`nix-wt-<repo-name>-<repo-id>-<overlay-name>.scope`. The scope is removed after
the command exits; the overlay launcher remains outside the scope so it can
unmount the merged filesystem afterward.

OverlayFS isolates writes made through the merged directory, but it is not a
security sandbox: the launched command can still access other paths permitted
to the user. Copilot's MXC policy provides that separate security boundary.

The name must start with a letter or number and may contain letters, numbers,
dots, underscores, and hyphens. The Nix dev shell provides `fuse-overlayfs`
and the required mount utilities.
