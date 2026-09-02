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

The bootstrap installs Nix with the Determinate Systems installer when needed,
then installs the appropriate flake output into the user profile.

## Update

```bash
./update-nix.sh
```

After a successful update, review and commit `nix/flake.lock`.

## Roll back

```bash
nix profile history
nix profile rollback
```

## Temporary development shell

```bash
nix develop ./nix
```
