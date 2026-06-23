# Nix-based WSL bootstrap

`bootstrap-wsl-nix.sh` is an alternative to `bootstrap-dev-shell.sh` for WSL
Ubuntu. It uses Nix and a flake under `nix/` instead of Homebrew to install
the CLI toolchain, including `wslu` (which routes `xdg-open` and `$BROWSER`
to the default Windows browser).

The Homebrew-based script remains the default for macOS and native Linux.
The two scripts target the same outcome on WSL but use different package
managers; pick one and stick with it on a given machine.

## When this path is a good fit

- Newer Ubuntu releases that haven't published `wslu` (or other tools) yet
  and where PPA workarounds are undesirable.
- You want a single declarative source of truth for tooling, shareable
  across machines via `flake.lock` and easy to roll back.
- You'd rather not run Linuxbrew under WSL.

## Usage

```bash
./bootstrap-wsl-nix.sh
```

The script:

1. Verifies it's running on WSL Ubuntu.
2. Ensures WSL interop is enabled in `/etc/wsl.conf`.
3. Enables systemd in `/etc/wsl.conf` via `[boot] systemd = true` (requires
   `wsl --shutdown` from PowerShell to take effect).
4. Appends an idempotent block to `/etc/gai.conf` so `getaddrinfo()`
   prefers IPv4 over IPv6 (uncomments `precedence ::ffff:0:0/96  100`
   and the `scopev4` NAT/loopback/link-local entries). This avoids long
   IPv6 timeouts on WSL2 when the upstream network is IPv4-only, without
   disabling IPv6 on the local link. The block is guarded by a
   `# codex-dev-shell: prefer IPv4 over IPv6` marker so reruns don't
   duplicate it.
5. Writes `/etc/sysctl.d/99-codex-dev-shell.conf` with editor/watcher
   defaults (`fs.inotify.max_user_watches`, `fs.inotify.max_user_instances`,
   `vm.max_map_count`) and reloads them in-place.
6. Installs the [Determinate Systems Nix installer][det] (multi-user,
   flakes enabled).
7. Installs the flake's `default` package into the user `nix profile`, so
   every tool lands in `~/.nix-profile/bin`.
8. Writes the same shell / Starship / git / jj templates as the Homebrew
   bootstrap. `templates/zsh/shell-tools.sh` installs a
   `~/.local/bin/wsl-browser` wrapper that probes Edge → Chrome →
   `wslview`, and exports `BROWSER` pointing at it. The wrapper avoids
   two related bugs: `explorer.exe`'s spurious Documents popup when
   invoked with a UNC cwd, and `sensible-browser`'s `eval "$BROWSER ..."`
   syntax error when `$BROWSER` contains spaces or `(x86)`. The template
   also symlinks the wrapper as `~/.local/bin/xdg-open` (so .NET's
   `Process.Start(url, UseShellExecute=true)` and MSAL interactive auth
   pick it up) and exports
   `ARTIFACTS_CREDENTIALPROVIDER_MSAL_ALLOW_BROKER=false` to disable
   the MSAL broker for `@microsoft/artifacts-npm-credprovider`, which on
   WSL bridges to Windows WAM via interop and triggers the same
   Documents popup.

For Windows-side `.wslconfig` recommendations (memory caps,
`networkingMode=mirrored`, DNS tunneling, etc.) see the "Recommended
Windows-side `.wslconfig`" section in [bootstrap.md](./bootstrap.md).

[det]: https://github.com/DeterminateSystems/nix-installer

## What's installed

See `nix/flake.nix`. It mirrors the CLI subset of `BREW_PACKAGES` in
`bootstrap-dev-shell.sh`, plus an in-flake `wslview` shim. (The upstream
`wslu` package was archived and removed from nixpkgs; the shim defined in
`flake.nix` forwards URLs and existing paths to `explorer.exe`, which is
enough for `$BROWSER=wslview` and `xdg-open URL`.)

The flake also installs JetBrains Mono Nerd Font and the Symbols-only
Nerd Font (`pkgs.nerd-fonts.jetbrains-mono`,
`pkgs.nerd-fonts.symbols-only`). Because fontconfig on non-NixOS does not
search `~/.nix-profile/share/fonts` by default, `bootstrap-wsl-nix.sh`
adds a `<dir>` entry to `~/.config/fontconfig/fonts.conf` and runs
`fc-cache` so the fonts are visible to `fc-list`, Ghostty, Windows
Terminal (via WSL), etc.

Out of scope for this script (handle separately if needed):

- VS Code launcher (`~/.local/bin/code` wrapper)

## Updating

```bash
# Refresh the nixpkgs pin in flake.lock
nix flake update ./nix

# Apply the new profile generation
nix profile upgrade '.*wsl-dev-tools.*'
```

## Rolling back

```bash
nix profile history
nix profile rollback
```

## Removing

```bash
nix profile remove '.*wsl-dev-tools.*'
# Full Nix uninstall (Determinate Systems installer):
/nix/nix-installer uninstall
```

## Running tools without a permanent install

If you'd rather not install into your user profile, the flake also exposes
a `devShell`:

```bash
nix develop ./nix
```

That drops you into a subshell with every tool on `PATH` and
`BROWSER=wslview` exported, leaving your global environment untouched.
