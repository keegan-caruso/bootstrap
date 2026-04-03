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
