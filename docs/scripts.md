# Scripts

## `bootstrap-dev-shell.sh`

Main machine bootstrap. It handles:

- OS detection
- Ubuntu base packages
- Homebrew installation and environment setup
- CLI package installation
- Node.js installation through `fnm`
- fallback global npm packages
- VS Code installation or WSL launcher setup
- Doom Emacs installation
- shell, prompt, Ghostty, and JJ config generation
- Git configuration

Run:

```bash
./bootstrap-dev-shell.sh
```

## `bootstrap-wsl-nix.sh`

WSL-only alternative bootstrap for Ubuntu that uses Nix + `nix/flake.nix`
instead of Homebrew to install the CLI toolchain.

Main characteristics:

- validates WSL + Ubuntu context
- ensures WSL interop and systemd configuration
- applies the same IPv4-preference and watcher/sysctl defaults as the main
  bootstrap
- installs Nix and the flake profile under `nix/`
- writes the same shell, prompt, and jj managed config blocks
- configures Git identity and related defaults

See [nix-wsl.md](nix-wsl.md) for full behavior and lifecycle commands.

Run:

```bash
./bootstrap-wsl-nix.sh
```

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
- light theme and opinionated keymap

Run:

```bash
./configure-zellij.sh
```

## `set-default-zsh.sh`

Small helper to set `zsh` as the default login shell for the current user on
Ubuntu.

Main characteristics:

- validates supported OS (macOS/Ubuntu detection)
- ensures `zsh` exists and is present in `/etc/shells`
- runs `chsh -s "$(command -v zsh)"` when needed on Ubuntu

Run:

```bash
./set-default-zsh.sh
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

## `agent-workflow.example.el`

Example data file for repo-local workflow defaults.

Projects can copy it to:

```elisp
agent-workflow.el
```

The file is read as data, not executed code.
