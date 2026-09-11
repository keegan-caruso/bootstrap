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

The development shell and Home Manager shell startup files export `DOTNET_ROOT`
from the same combined .NET SDK package. Native .NET apphosts (including test
executables launched by `dotnet test`) need this to locate `libhostfxr` in the
Nix store; putting `dotnet` on `PATH` alone is insufficient. This also applies
to `nix-wt` and `sr-wt` child processes.

The shell environment also exposes fnm's stable default runtime at
`$FNM_DIR/aliases/default/bin` (defaulting to `${XDG_DATA_HOME:-~/.local/share}/fnm`).
This makes Node tools available to noninteractive Nix shells without inheriting
a temporary fnm multishell path. An explicitly selected runtime remains ahead
of this fallback. Node and global npm tools are still installed by bootstrap,
not by Nix.

Nix provisions `csharp-ls`, and Home Manager writes its absolute executable path
to `~/.copilot/lsp-config.json`. Restart Copilot or use `/lsp reload` after
activation to load the server.

Linux profiles include `bubblewrap`, `slirp4netns`, and `iptables` for Copilot's
filesystem and firewall-network sandbox. `configure-copilot-sandbox.sh` refuses
to enable the sandbox if any required executable is missing, leaving existing
settings intact.

The sandbox exposes the Nix profile directory, fnm runtimes, and
`~/.local/bin` read-only. Mounting `/nix/store` alone does not make the profile
symlinks on `PATH` visible.

To update these paths without enabling a disabled sandbox:

```bash
./configure-copilot-sandbox.sh --configure-only
```

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
Updates also reconcile the managed shell loader blocks, so legacy inline
configuration cannot mask the newly activated Home Manager files. Shell plugin
caches track resolved source paths to refresh across Nix store generations,
whose source timestamps are normalized.

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
