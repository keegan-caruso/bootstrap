# Templates

Home Manager reads tracked templates from `nix/templates/` and installs the
generated user configuration. The bootstrap retains small loader blocks in
existing shell files and renders the identity-dependent Jujutsu configuration.

## Template Files

- `nix/templates/zsh/path.sh`
- `nix/templates/zsh/interactive.sh`
- `nix/templates/zsh/prompt.sh`
- `nix/templates/zsh/shell-tools.sh`
- `nix/templates/zsh/syntax-highlighting.sh`
- `nix/templates/bash/aliases.sh`
- `nix/templates/starship.toml`
- `nix/templates/typescript-language-server`
- `nix/templates/ghostty/config`
- `nix/templates/jj/config.toml.tmpl`
- `nix/templates/copilot/playwright.instructions.md`
- `nix/templates/git-credential-manager-wsl`
- `nix/templates/wsl-browser`

## What They Feed

- Zsh templates -> `~/.config/codex-dev-shell/zshrc`, sourced by the managed
  loader block in `~/.zshrc`
- `nix/templates/bash/aliases.sh` -> `~/.config/codex-dev-shell/bashrc`,
  sourced by the managed WSL loader block in `~/.bashrc`
- `nix/templates/starship.toml` -> `~/.config/starship.toml`
- `nix/templates/typescript-language-server` ->
  `~/.local/bin/typescript-language-server`
- `nix/templates/ghostty/config` -> `~/.config/ghostty/config`
- `nix/templates/copilot/playwright.instructions.md` ->
  `~/.copilot/instructions/playwright.instructions.md`
- WSL helper templates -> executables under `~/.local/bin`
- `nix/templates/jj/config.toml.tmpl` -> rendered into
  `~/.config/jj/config.toml` by the bootstrap

## JJ Template Rendering

`nix/templates/jj/config.toml.tmpl` is rendered with:

- `__GIT_NAME__`
- `__GIT_EMAIL__`

Those values come from the same identity collected for Git config.
