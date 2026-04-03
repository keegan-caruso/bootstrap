# Bootstrap

The main bootstrap entry point is:

```bash
./bootstrap-dev-shell.sh
```

## What It Installs

The script installs and configures:

- Homebrew
- core CLI tools such as `fd`, `rg`, `bat`, `eza`, `git`, `gh`, `jj`,
  `jq`, `zellij`, `starship`
- utility tools such as `delta`, `zoxide`, `hyperfine`, `tokei`, `dust`,
  `duf`, `bottom`, `procs`, `ncdu`, `xh`, `doggo`
- JavaScript toolchain support through `fnm`, Node.js LTS, Corepack,
  `prettier`, `eslint_d`
- Python support through `uv`, `ruff`, and `ty`
- Rust support through `rust-analyzer`
- TOML support through `taplo`
- shell and markup tooling through `shellcheck`, `shfmt`,
  `markdownlint-cli2`, `pandoc`, `yamllint`, `yq`
- VS Code
- Doom Emacs
- global Git and Jujutsu identity/config
- fallback/editor fonts such as JetBrains Mono Nerd Font, Symbols Nerd Font
  Mono, and Symbola

The bootstrap also installs machine-level fallback npm packages:

- `typescript`
- `typescript-language-server`

These are fallbacks. The editor is designed to prefer project-local JS/TS
tools when present.

## Platform Behavior

### macOS

The script:

- uses Homebrew under `/opt/homebrew` or `/usr/local`
- installs `emacs-plus-app` from `d12frosted/emacs-plus`
- installs JetBrains Mono Nerd Font through Homebrew Casks
- installs Symbols Nerd Font Mono through Homebrew Casks
- installs the Symbola fallback font into `~/Library/Fonts`
- installs Ghostty
- installs VS Code through Homebrew Casks

### Ubuntu

The script:

- installs a small base package set with `apt-get`
- installs the rest of the CLI stack through Homebrew
- installs Emacs through Homebrew
- installs VS Code through Microsoft’s apt repository
- installs JetBrains Mono Nerd Font, Symbols Nerd Font Mono, and Symbola into
  the user font directory

### WSL

The script detects WSL automatically and changes behavior:

- warns if the repo lives under `/mnt/*`
- skips Ghostty installation
- skips `chsh`
- uses a Windows-hosted `code` launcher instead of trying to install Linux
  VS Code
- writes a guarded `.bashrc` block so interactive bash sessions hand off to
  `zsh`
- adds Windows interop helpers through shell config

## Shell and Prompt Setup

The bootstrap writes managed blocks into:

- `~/.zshrc`
- `~/.bashrc` on WSL
- `~/.config/starship.toml`
- `~/.config/ghostty/config`
- `~/.config/jj/config.toml`

Those blocks are sourced from tracked files under `templates/`.

## Doom Emacs Setup

The bootstrap:

- installs Doom Emacs into `~/.emacs.d`
- copies the tracked `doom/` tree into `~/.doom.d`
- runs `~/.emacs.d/bin/doom install --force`

If `~/.emacs.d` already exists and is not the Doom Emacs repository, the
script stops instead of overwriting it.

## Git and JJ Setup

The bootstrap configures:

- `user.name`
- `user.email`
- `delta`
- `merge.conflictStyle=zdiff3`
- `fetch.prune=true`
- `init.defaultBranch=main`

On WSL it also sets:

- `core.fileMode=false`
- `core.autocrlf=input`
- `credential.helper=manager-core` if Git Credential Manager is already
  present

JJ config is generated from `templates/jj/config.toml.tmpl` using the same
Git identity values.

If `dotnet` is already installed, the bootstrap also installs `csharpier` as a
global .NET tool and exposes it through `~/.local/bin`.
