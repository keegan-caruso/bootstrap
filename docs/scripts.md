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
updated flake, and upgrades the installed development profile generation.
It activates the installed Nix profile automatically when `nix` is not already
on `PATH`.

Run:

```bash
./update-nix.sh
```

After it succeeds, review and commit the `nix/flake.lock` change.

## `test-nix.sh`

Evaluates the flake for every supported system and builds the current machine's
tool environment locally.

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
`${XDG_STATE_HOME:-~/.local/state}/nix-wt/` and a branch named
`user/keegancaruso/<overlay-name>`. The source checkout is the read-only lower
layer and must be clean.

Start Agency Copilot from within a repository:

```zsh
/path/to/bootstrap/nix-wt issue-123 -- agency cp
```

Run for an explicit repository:

```zsh
./nix-wt issue-123 -C /path/to/repository -- agency cp
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
Overlay: ~/.local/state/nix-wt/<repo-name>-<repo-id>/issue-123/merged
State:   ~/.local/state/nix-wt/<repo-name>-<repo-id>/issue-123
Branch:  user/keegancaruso/issue-123
```

The overlay is unmounted when the command exits, while its writable layer
remains available for another `nix-wt` session with the same repository and
overlay name. The launcher records the repository path to verify the state
belongs to the expected checkout. It also records the base commit and refuses
to reopen the overlay if the source checkout has moved; use a new overlay name
in that case. Commits and refs created in the overlay remain in its writable
layer, so push the branch before deleting that state. Do not change the source
checkout while overlays are mounted.

The command runs in a collectible systemd user scope named
`nix-wt-<repo-name>-<repo-id>-<overlay-name>.scope`. The scope is removed after
the command exits; the overlay launcher remains outside the scope so it can
unmount the merged filesystem afterward.

OverlayFS isolates writes made through the merged directory, but it is not a
security sandbox: the launched command can still access other paths permitted
to the user.

The name must start with a letter or number and may contain letters, numbers,
dots, underscores, and hyphens. The Nix dev shell provides `fuse-overlayfs`,
mount utilities, and an `agency` wrapper for
`~/.config/agency/CurrentVersion/agency`.
