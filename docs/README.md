# Docs

This repo is a personal bootstrap for a terminal-first development environment.

Use these docs as the main reference:

- [bootstrap.md](bootstrap.md): machine bootstrap behavior and installed tooling
- [nix.md](nix.md): flake outputs, updates, and rollback
- [scripts.md](scripts.md): purpose and usage of each top-level script
- [templates.md](templates.md): tracked shell and config templates managed by
  Home Manager and the bootstrap
- [wsl-btrfs.md](wsl-btrfs.md): set up a separate Btrfs data VHDX for WSL,
  including fstab mounts and Windows sign-in automation
- [copilot-extensions.md](copilot-extensions.md): tracked Azure DevOps and
  Linux clipboard extensions, installation, and prerequisites
- [tools/readme.md](tools/readme.md): installed tool reference pages

## Repo Layout

- `bootstrap-nix.sh`: main bootstrap script
- `configure-zellij.sh`: writes `~/.config/zellij/config.kdl`
- `Mount-DataBtrfs.ps1`: attaches and mounts an existing Btrfs data VHDX
- `Register-DataBtrfsStartup.ps1`: registers the elevated Windows sign-in task
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
