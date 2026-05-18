# Scripts

## `bootstrap-dev-shell.sh`

Main machine bootstrap. It handles:

- OS detection
- Ubuntu base packages
- Homebrew installation and environment setup
- CLI package installation
- Node.js installation through `fnm`
- fallback global npm packages
- VS Code installation or WSL launcher setup
- Doom Emacs installation
- shell, prompt, Ghostty, and JJ config generation
- Git configuration

Run:

```bash
./bootstrap-dev-shell.sh
```

## `configure-zellij.sh`

Writes a managed `~/.config/zellij/config.kdl`.

Main characteristics:

- vim-like pane and tab movement
- clipboard integration using the first available helper:
  - `clip.exe`
  - `pbcopy`
  - `wl-copy`
  - `xclip`
  - `xsel`
- light theme and opinionated keymap

Run:

```bash
./configure-zellij.sh
```

## `launch-wt-wsl.ps1`

Launches Windows Terminal directly into WSL.

Parameters:

- `-Distro`: optional WSL distro name
- `-WorkingDirectory`: WSL path such as `~`, `/home/...`, or `/mnt/c/...`
- `-Shell`: shell to exec inside WSL, default `zsh`
- `-WtPath`: override path to `wt.exe`
- `-NewWindow`: open a new Windows Terminal window

Run from Windows PowerShell:

```powershell
.\launch-wt-wsl.ps1
```

Examples:

```powershell
.\launch-wt-wsl.ps1 -Distro Ubuntu
.\launch-wt-wsl.ps1 -Distro Ubuntu -WorkingDirectory /home/your-user/src
.\launch-wt-wsl.ps1 -NewWindow
```

## `update-machine-agents-shell-commands.sh`

Adds or updates a managed section in machine-scoped `agents.md` for the
current shell command tools:

- `bash`
- `read_bash`
- `write_bash`
- `stop_bash`

Defaults to:

```text
~/.copilot/agents.md
```

Managed section content source:

- `templates/machine-agents/shell-command-tools.md`

Targeting options:

- `--file <path>` (repeatable for multi-target updates)
- first positional argument (legacy single target), or
- `MACHINE_AGENTS_MD` environment variable (legacy single target)

Additional options:

- `--section <name>`: override the marker section name (default: `shell-commands`)
- `--dry-run`: print diffs for pending updates without writing files
- `--check`: exit non-zero if any target file would change
- `--help`: print usage

Machine-scoped files matrix:

| Tool | Typical path | Example |
| --- | --- | --- |
| GitHub Copilot | `~/.copilot/agents.md` | `./update-machine-agents-shell-commands.sh --file ~/.copilot/agents.md` |
| Codex | `~/.codex/AGENTS.md` | `./update-machine-agents-shell-commands.sh --file ~/.codex/AGENTS.md` |

Examples:

```bash
# Default target (~/.copilot/agents.md)
./update-machine-agents-shell-commands.sh

# Update both Copilot and Codex targets in one run
./update-machine-agents-shell-commands.sh \
  --file ~/.copilot/agents.md \
  --file ~/.codex/AGENTS.md

# Preview diffs without writing
./update-machine-agents-shell-commands.sh --dry-run --file ~/.codex/AGENTS.md

# CI/pre-commit check mode
./update-machine-agents-shell-commands.sh --check --file ~/.copilot/agents.md
```

Bootstrap integration:

- set `BOOTSTRAP_UPDATE_MACHINE_AGENTS=1` before running `./bootstrap-dev-shell.sh`
  to invoke the updater as an optional bootstrap step.

The updater normalizes line endings and trailing blank lines in the managed
section to reduce unnecessary diffs across systems.

## `agent-workflow.example.el`

Example data file for repo-local workflow defaults.

Projects can copy it to:

```elisp
agent-workflow.el
```

The file is read as data, not executed code.
