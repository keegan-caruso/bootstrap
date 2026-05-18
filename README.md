# bootstrap

Personal bootstrap scripts for a terminal-first development environment.

This repo sets up:

- shell tooling via Homebrew
- `zsh` + Starship + modern CLI aliases
- VS Code, including WSL-friendly launch behavior
- Doom Emacs with split language config
- Zellij configuration
- agent-oriented editor workflows for Codex, Claude, and GitHub Copilot

## Start Here

- [docs/README.md](docs/README.md): docs index
- [docs/bootstrap.md](docs/bootstrap.md):
  bootstrap behavior and installed tooling
- [docs/scripts.md](docs/scripts.md):
  top-level scripts
- [docs/doom.md](docs/doom.md):
  Doom config and editor behavior
- [docs/emacs.md](docs/emacs.md):
  getting started with Emacs in this setup
- [docs/workflows.md](docs/workflows.md):
  agent workflows and keybindings
- [docs/languages.md](docs/languages.md):
  language-specific support
- [docs/templates.md](docs/templates.md):
  tracked template files
- [docs/tools/readme.md](docs/tools/readme.md):
  installed tool reference pages

## Quick Start

Bootstrap a machine:

```bash
./bootstrap-dev-shell.sh
```

Configure Zellij:

```bash
./configure-zellij.sh
```

Launch WSL from Windows Terminal:

```powershell
.\launch-wt-wsl.ps1
```

## Notes

- The bootstrap is intentionally opinionated.
- Doom config changes should usually be made in
  [doom/](doom/), not directly in
  generated files under `~/.doom.d`.
- Some language workflows assume the underlying toolchain already exists.
