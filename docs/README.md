# Docs

This repo is a personal bootstrap for a terminal-first development environment.

Use these docs as the main reference:

- [bootstrap.md](bootstrap.md): machine bootstrap behavior and installed tooling
- [nix.md](nix.md): flake outputs, updates, and rollback
- [scripts.md](scripts.md): purpose and usage of each top-level script
- [templates.md](templates.md): tracked shell and config templates managed by
  Home Manager and the bootstrap
- [tools/readme.md](tools/readme.md): installed tool reference pages

## Repo Layout

- `bootstrap-nix.sh`: main bootstrap script
- `configure-zellij.sh`: writes `~/.config/zellij/config.kdl`
- `launch-wt-wsl.ps1`: launches Windows Terminal into WSL
- `nix/home.nix`: declarative user configuration managed by Home Manager
- `nix/templates/`: shell and app configuration sources

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
