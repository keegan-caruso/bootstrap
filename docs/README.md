# Docs

This repo is a personal bootstrap for a terminal-first development environment.

Use these docs as the main reference:

- [bootstrap.md](bootstrap.md): machine bootstrap behavior and installed tooling
- [scripts.md](scripts.md): purpose and usage of each top-level script
- [doom.md](doom.md): Doom Emacs structure, modules, and editor behavior
- [emacs.md](emacs.md): how to get started with Emacs in this setup
- [workflows.md](workflows.md): agent workflows, notes, terminals, and keybindings
- [languages.md](languages.md): language-specific editor and terminal support
- [templates.md](templates.md): tracked shell and config templates copied by
  the bootstrap
- [tools/readme.md](tools/readme.md): installed tool reference pages

## Repo Layout

- `bootstrap-dev-shell.sh`: main bootstrap script
- `configure-zellij.sh`: writes `~/.config/zellij/config.kdl`
- `launch-wt-wsl.ps1`: launches Windows Terminal into WSL
- `doom/`: Doom Emacs config templates copied into `~/.doom.d`
- `templates/`: shell and app config templates read by the bootstrap
- `agent-workflow.example.el`: example repo-local workflow defaults

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
