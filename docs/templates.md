# Templates

Bootstrap reads tracked templates from `templates/` and writes managed
blocks into user config files.

## Template Files

- `templates/zsh/path.sh`
- `templates/zsh/prompt.sh`
- `templates/zsh/shell-tools.sh`
- `templates/bash/wsl-zsh-handoff.sh`
- `templates/starship.toml`
- `templates/ghostty/config`
- `templates/jj/config.toml.tmpl`

## What They Feed

- `templates/zsh/path.sh` -> managed path block in `~/.zshrc`
- `templates/zsh/prompt.sh` -> managed prompt block in `~/.zshrc`
- `templates/zsh/shell-tools.sh` -> managed shell helper block in `~/.zshrc`
- `templates/bash/wsl-zsh-handoff.sh` -> managed WSL handoff block in `~/.bashrc`
- `templates/starship.toml` -> managed block in `~/.config/starship.toml`
- `templates/ghostty/config` -> managed block in `~/.config/ghostty/config`
- `templates/jj/config.toml.tmpl` -> rendered into `~/.config/jj/config.toml`

## JJ Template Rendering

`templates/jj/config.toml.tmpl` is rendered with:

- `__GIT_NAME__`
- `__GIT_EMAIL__`

Those values come from the same identity collected for Git config.
