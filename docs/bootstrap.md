# Bootstrap

The main bootstrap entry point is:

```bash
./bootstrap-nix.sh
```

`bootstrap-dev-shell.sh` and `bootstrap-wsl-nix.sh` are compatibility wrappers
for the same command.

## Package ownership

Nix is the source of truth for native tools, including:

- shell and navigation tools such as `zsh`, `fzf`, `fd`, `bat`, `eza`,
  `zoxide`, Starship, and Zsh plugins
- Git, GitHub CLI, Jujutsu, Delta, and common data/markup tools
- .NET SDK 8 and 10 plus CSharpier
- Python tools including `uv`, `ruff`, and `ty`
- Rust-based tools including `rust-analyzer`, `bottom`, `dust`, `taplo`,
  `tokei`, and Zellij
- JetBrains Mono Nerd Font, Symbols Nerd Font, and Symbola
- Ghostty on native Linux and Apple Silicon macOS

The bootstrap uses `fnm` from Nix to install Node.js LTS. npm owns the tools
that are distributed natively through npm:

- `typescript@7.0.2`
- `markdownlint-cli2@0.23.2`
- `oxfmt@0.66.0`
- `oxlint@1.81.0`

The installed `typescript-language-server` compatibility command runs
TypeScript 7's native `tsc --lsp` mode.

## npm registry configuration

npm installation honors normal project, user, and global `.npmrc` files,
including scoped registries and authentication. `NPM_CONFIG_REGISTRY` works
normally. The bootstrap also accepts a one-run override:

```bash
BOOTSTRAP_NPM_REGISTRY=https://registry.example.test/ ./bootstrap-nix.sh
```

The bootstrap confirms that npm resolved a registry without printing the URL or
credentials.

## Supported platforms

- Ubuntu 24.04 and 26.04, including WSL
- Apple Silicon macOS

The pinned nixpkgs revision no longer supports Intel macOS.

Ubuntu uses apt only for host integration prerequisites such as CA
certificates, the Nix installer, and Secret Service support. Development tools
come from the pinned Nix flake.

When Nix is absent, the bootstrap downloads the pinned Determinate Nix
installer release and verifies its published SHA-256 digest before running it.

WSL additionally configures systemd, editor/watch limits, browser integration,
and Windows Git Credential Manager. It does not install Ghostty. VS Code is not
installed or configured on any platform.

## Configuration

The bootstrap writes managed blocks into:

- `~/.zshenv`
- `~/.zshrc`
- `~/.bashrc` on WSL
- `~/.config/starship.toml`
- `~/.config/ghostty/config` outside WSL
- `~/.config/jj/config.toml`

Global Git configuration includes identity, Delta, `zdiff3`, fetch pruning,
and a default `main` branch. WSL also uses Windows Git Credential Manager.

## Updating

```bash
./update-nix.sh
```

The updater refreshes `nix/flake.lock`, evaluates and builds the flake, and
atomically upgrades the dedicated bootstrap profile.

## Local checks

```bash
./test-bootstrap.sh
./test-nix.sh
```

The bootstrap integration test uses an isolated temporary home directory and
stubbed external commands. It checks idempotent managed configuration,
Homebrew-block removal, npm registry overrides, and WSL/native flake output
selection without modifying the real home directory.

The Nix test runs the bootstrap integration test, evaluates every supported
system, and builds the tool environment for the current machine. It does not
use CI or a container runtime.
