# Docs

This repo is a personal bootstrap for a terminal-first development environment.

Use these docs as the main reference:

- [bootstrap.md](bootstrap.md): machine bootstrap behavior and installed tooling
- [scripts.md](scripts.md): purpose and usage of each top-level script
- [templates.md](templates.md): tracked shell and config templates copied by
  the bootstrap
- [tools/readme.md](tools/readme.md): installed tool reference pages

## Repo Layout

- `bootstrap-dev-shell.sh`: main bootstrap script
- `configure-zellij.sh`: writes `~/.config/zellij/config.kdl`
- `launch-wt-wsl.ps1`: launches Windows Terminal into WSL
- `templates/`: shell and app config templates read by the bootstrap

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
