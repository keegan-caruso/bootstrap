# bootstrap

Personal bootstrap scripts for a terminal-first development environment.

This repo sets up:

- shell tooling via Homebrew
- `zsh` + Starship + modern CLI aliases, plus completion / history defaults, autosuggestions, and syntax highlighting
- VS Code, including WSL-friendly launch behavior
- Zellij configuration

## Start Here

- [docs/README.md](/Users/keegancaruso/source/bootstrap/docs/README.md): docs index
- [docs/bootstrap.md](/Users/keegancaruso/source/bootstrap/docs/bootstrap.md):
  bootstrap behavior and installed tooling
- [docs/scripts.md](/Users/keegancaruso/source/bootstrap/docs/scripts.md):
  top-level scripts
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
- Some language workflows assume the underlying toolchain already exists.
