# Nix environment

The pinned flake under `nix/` is the native package authority for the
development environment.

## Outputs

- `default`: CLI tools and fonts, used on WSL
- `workstation`: CLI tools, fonts, and Ghostty, used on native Linux and macOS
- `desktop`: Ghostty only
- `devShell`: the CLI environment used by `nix-wt`
- `homeConfigurations`: Home Manager configurations for WSL, native Linux,
  and Apple Silicon macOS

Supported Nix systems are `x86_64-linux`, `aarch64-linux`, and
`aarch64-darwin`.

The shared platform helper selects `default` on WSL and `workstation` on native
Linux and macOS for bootstrap, update, and local build checks.

The flake exposes the official `nixfmt` from the pinned nixpkgs revision as its
formatter.

## Install

```bash
./bootstrap-nix.sh
```

The bootstrap installs Nix with the pinned Determinate Systems installer
`v3.22.2` when needed. It downloads the immutable release script and verifies
its published SHA-256 digest before execution, then installs the appropriate
flake output into a dedicated profile at
`${XDG_STATE_HOME:-~/.local/state}/nix/profiles/bootstrap`.
It builds the desired output before changing the profile. Existing matching
entries are upgraded in place; output or checkout-path migrations atomically
switch to a complete replacement generation.

The bootstrap then activates the matching Home Manager configuration. Home
Manager owns generated shell configuration, Starship, Ghostty, Copilot
instructions, fonts, and user-level helper executables. Small managed loader
blocks remain in `.zshrc` and WSL `.bashrc` so unrelated user content is
preserved. Home Manager configures fontconfig on Linux and installs native
font copies under `~/Library/Fonts/HomeManager` on macOS.
During the first migration, bootstrap refuses to replace a legacy `.zshenv`,
Starship, or Ghostty file that contains content outside its managed block.
Existing custom WSL `~/.local/bin/xdg-open` implementations are also preserved.

## Update

```bash
./update-nix.sh
```

After a successful update, review and commit `nix/flake.lock`.

## Roll back

```bash
profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/bootstrap"
nix profile history --profile "$profile"
nix profile rollback --profile "$profile"
```

## Temporary development shell

```bash
nix develop ./nix
```

## Checks

```bash
./test-nix.sh
```

This first exercises bootstrap behavior in an isolated temporary home
directory, checks Nix formatting, evaluates every supported system, and builds
the current machine's tool environment.
