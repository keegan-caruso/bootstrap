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

- [docs/README.md](/Users/keegancaruso/source/bootstrap/docs/README.md): docs index
- [docs/bootstrap.md](/Users/keegancaruso/source/bootstrap/docs/bootstrap.md):
  bootstrap behavior and installed tooling
- [docs/scripts.md](/Users/keegancaruso/source/bootstrap/docs/scripts.md):
  top-level scripts
- [docs/doom.md](/Users/keegancaruso/source/bootstrap/docs/doom.md):
  Doom config and editor behavior
- [docs/emacs.md](/Users/keegancaruso/source/bootstrap/docs/emacs.md):
  getting started with Emacs in this setup
- [docs/workflows.md](/Users/keegancaruso/source/bootstrap/docs/workflows.md):
  agent workflows and keybindings
- [docs/languages.md](/Users/keegancaruso/source/bootstrap/docs/languages.md):
  language-specific support
- [docs/templates.md](/Users/keegancaruso/source/bootstrap/docs/templates.md):
  tracked template files
- [docs/tools/readme.md](/Users/keegancaruso/source/bootstrap/docs/tools/readme.md):
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
  [doom/](/Users/keegancaruso/source/bootstrap/doom), not directly in
  generated files under `~/.doom.d`.
- Some language workflows assume the underlying toolchain already exists.
