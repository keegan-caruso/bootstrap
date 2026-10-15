# Bootstrap

The main bootstrap entry point is:

```bash
./bootstrap-nix.sh
```

`bootstrap-dev-shell.sh` and `bootstrap-wsl-nix.sh` are compatibility wrappers
for the same command.

## Shell profiles

On the first run, bootstrap asks which shell profile to use. Press Enter for
the existing `starship` default, or choose `minimal` for a directory-only Zsh
prompt without Starship, Git-status detection, or zoxide tracking and jump
commands. The minimal profile starts interactive shells in `~/repos` when
that directory exists; otherwise it preserves the current directory. Both
profiles retain completion, autosuggestions, syntax highlighting, fzf, and
the lazy Node.js setup.

The choice is saved in `~/.config/codex-dev-shell/shell-profile`. Later
bootstrap runs reuse it without prompting, and `update-nix.sh` preserves it.
For scripted selection or to change an existing choice:

```bash
BOOTSTRAP_SHELL_PROFILE=minimal ./bootstrap-nix.sh
BOOTSTRAP_SHELL_PROFILE=starship ./bootstrap-nix.sh
```

Open a new shell or run `exec zsh` after changing profiles. Existing
installations without a saved choice continue using Starship until bootstrap
is rerun. The minimal profile skips Starship and zoxide initialization rather
than starting them and disabling their hooks afterward. Their packages and
existing data remain installed, and user-owned `.zshrc` customizations are
preserved.

## Package ownership

Nix is the source of truth for native tools, including:

- shell and navigation tools such as `zsh`, `fzf`, `fd`, `bat`, `eza`,
  `zoxide`, Starship, and Zsh plugins
- Git, GitHub CLI, Jujutsu, Delta, and common data/markup tools
- Linux-native PowerShell on Linux and WSL
- .NET SDK 10 plus CSharpier, `ilspycmd` (`ilspy`), and `dotnet-csi` (`csi`)
- infrastructure tools including Terraform
- Python tools including `uv`, `ruff`, and `ty`
- Rust-based tools including `rust-analyzer`, `bottom`, `dust`, `taplo`,
  `tokei`, and Zellij
- Ubuntu Mono, Symbols Nerd Font, and Symbola
- Ghostty on native Linux and Apple Silicon macOS

The bootstrap uses `fnm` from Nix to refresh Node.js to the latest LTS on each
run. npm owns the tools that are distributed natively through npm:

- `@microsoft/artifacts-npm-credprovider@1.2.1`
- `typescript@7.0.2`
- `markdownlint-cli2@0.23.3`
- `oxfmt@0.73.0`
- `oxlint@1.88.0`

The Artifacts npm credential provider is installed from Microsoft's public
Azure Artifacts feed. Other npm tools continue to use the registry resolved
from the user's npm configuration or `BOOTSTRAP_NPM_REGISTRY`.

The installed `typescript-language-server` compatibility command runs
TypeScript 7's native `tsc --lsp` mode.

After the Nix profile and shell configuration are ready, the bootstrap removes
the old CSharpier symlink and cached .NET installer. It preserves a non-empty
`~/.dotnet` because the previous bootstrap allowed a custom `DOTNET_ROOT`, so
ownership of that directory cannot be inferred safely. To explicitly remove
it during migration:

```bash
BOOTSTRAP_REMOVE_LEGACY_DOTNET=1 ./bootstrap-nix.sh
```

User-managed Cargo state is not removed. The superseded npm
`typescript-language-server` package is uninstalled from the active fnm runtime
before the compatibility command is installed.

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
- Fedora 45 on a mutable installation, such as Workstation
- Apple Silicon macOS

The pinned nixpkgs revision no longer supports Intel macOS.
Fedora Atomic desktops and Fedora on WSL are not supported.

Ubuntu uses apt only for host integration prerequisites such as CA
certificates, the Nix installer, and Secret Service support. Development tools
come from the pinned Nix flake, including Bubblewrap for Copilot CLI command
sandboxing and rootless Podman and Buildah. The bootstrap installs Ubuntu's
setuid `newuidmap` and `newgidmap` helpers, allocates subordinate UID/GID ranges
when needed, and enables unprivileged user namespaces when the host has them
disabled.

Fedora uses dnf for equivalent host prerequisites, including
`util-linux` and `policycoreutils`. The curl executable is requested by path so
either Fedora's full or minimal curl package can satisfy it.

When Nix is absent, the bootstrap downloads the pinned Determinate Nix
installer release and verifies its published SHA-256 digest before running it.
On Fedora, the installer provisions its SELinux policy using the host tools;
the bootstrap does not disable SELinux.

Fedora support covers host bootstrap and default-shell setup. Ghostty graphics,
Copilot sandboxing, Playwright, and overlay sessions have not been validated on
Fedora and are unchanged. The existing native Linux profile still includes
Ghostty.

To select the installed Zsh as the default shell on Ubuntu or Fedora:

```bash
./set-default-zsh.sh
```

WSL additionally configures systemd, editor/watch limits, browser integration,
and Windows Git Credential Manager. It does not install Ghostty. VS Code is not
installed or configured on any platform. The managed WSL shell path excludes
the Windows VS Code CLI while preserving other Windows interoperability paths.

## Configuration

The bootstrap writes managed blocks into:

- `~/.zshrc`
- `~/.bashrc` on WSL
- `~/.config/jj/config.toml`

Home Manager owns:

- `~/.zshenv`
- generated shell configuration under `~/.config/codex-dev-shell`
- `~/.config/starship.toml`
- `~/.config/ghostty/config` outside WSL
- `~/.copilot/instructions/playwright.instructions.md`
- user-level browser and TypeScript language-server helpers
- user fonts and platform-specific font discovery

Global Git configuration includes identity, Delta, `zdiff3`, fetch pruning,
and a default `main` branch. WSL configures native Linux Git to use Windows Git
Credential Manager directly for clone, fetch, and push. Install Git for Windows
before running bootstrap; the expected executable is
`/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe`.
The bootstrap applies these settings and removes legacy `manager-wsl` entries:

```bash
git config --global credential.helper '/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe'
git config --global credential.https://dev.azure.com.useHttpPath true
```

The global credential helper is replaced, while other host-specific helper
settings remain intact. Azure DevOps credentials are matched by repository
path. No per-command authorization-header prefix or custom wrapper is needed.

WSL also installs the verified Linux AzureAuth release under
`~/.local/share/azureauth`, with a link at `~/.local/bin/azureauth`, for tools that
use AzureAuth independently of Git.

## Updating

```bash
./update-nix.sh
```

The updater refreshes `nix/flake.lock`, evaluates and builds the flake,
atomically upgrades the dedicated bootstrap profile, and activates the matching
Home Manager generation.

## Local checks

```bash
./test-bootstrap.sh
./test-nix.sh
```

The bootstrap integration test uses an isolated temporary home directory and
stubbed external commands. It checks idempotent managed configuration,
Homebrew-block removal, npm registry overrides, and WSL/native flake output
selection, plus legacy tool cleanup, without modifying the real home directory.
It also runs `test-shell-profile.sh`, which checks saved profile selection,
switching profiles, and minimal shells without Git, Starship, or zoxide calls.

The Nix test runs the bootstrap integration test, evaluates every supported
system, and builds the tool environment for the current machine. It does not
use CI or a container runtime.
