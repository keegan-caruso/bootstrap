# bootstrap

Personal bootstrap scripts for a terminal-first development environment.

This repo sets up:

- shell and development tooling through Nix
- `zsh` + Starship + modern CLI aliases, plus completion / history defaults, autosuggestions, and syntax highlighting
- Ghostty on native Linux and Apple Silicon macOS
- Zellij configuration

## Start Here

- [docs/README.md](docs/README.md): docs index
- [docs/bootstrap.md](docs/bootstrap.md):
  bootstrap behavior and installed tooling
- [docs/scripts.md](docs/scripts.md):
  top-level scripts
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

Configure the global Copilot CLI sandbox:

```bash
./configure-copilot-sandbox.sh
```

Launch WSL from Windows Terminal:

```powershell
.\launch-wt-wsl.ps1
```

## Notes

- The bootstrap is intentionally opinionated.
- Some language workflows assume the underlying toolchain already exists.
