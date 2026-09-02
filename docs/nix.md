# Nix environment

The pinned flake under `nix/` is the native package authority for the
development environment.

## Outputs

- `default`: CLI tools and fonts, used on WSL
- `workstation`: CLI tools, fonts, and Ghostty, used on native Linux and macOS
- `desktop`: Ghostty only
- `devShell`: the CLI environment plus the local `agency` wrapper

Supported Nix systems are `x86_64-linux`, `aarch64-linux`, and
`aarch64-darwin`.

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
