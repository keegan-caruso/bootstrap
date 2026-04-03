# Emacs

This repo uses Doom Emacs as an editor and review surface.

It is not the main terminal control plane. The intended split is:

- Ghostty or Windows Terminal plus Zellij for long-lived terminal work
- Emacs for editing, search, review, notes, and launching project terminals

## First Start

1. Run [bootstrap-dev-shell.sh](/Users/keegancaruso/source/bootstrap/bootstrap-dev-shell.sh).
2. Start Emacs with `emacs`.
3. Let Doom finish its first-run package setup if prompted.
4. Open a project directory and start using leader bindings.

On macOS, the bootstrap now installs `emacs-plus-app`, which gives you a
native-compilation-enabled Emacs build.

If you change tracked Doom config in this repo later, copy it back into
`~/.doom.d` by rerunning the bootstrap, then run:

```bash
~/.emacs.d/bin/doom sync
```

## Where the Config Lives

Tracked source of truth:

- [doom/init.el](/Users/keegancaruso/source/bootstrap/doom/init.el)
- [doom/config.el](/Users/keegancaruso/source/bootstrap/doom/config.el)
- [doom/packages.el](/Users/keegancaruso/source/bootstrap/doom/packages.el)
- [doom/config/core.el](/Users/keegancaruso/source/bootstrap/doom/config/core.el)
- [doom/config/javascript.el](/Users/keegancaruso/source/bootstrap/doom/config/javascript.el)
- [doom/config/dotnet.el](/Users/keegancaruso/source/bootstrap/doom/config/dotnet.el)
- [doom/config/python.el](/Users/keegancaruso/source/bootstrap/doom/config/python.el)
- [doom/config/rust.el](/Users/keegancaruso/source/bootstrap/doom/config/rust.el)
- [doom/config/toml.el](/Users/keegancaruso/source/bootstrap/doom/config/toml.el)

Generated local config:

- `~/.doom.d`

Edit the tracked repo files, not the generated copy, when you want changes to
stick.

## How It Interacts With This Setup

The bootstrap installs Doom Emacs and copies the repo's `doom/` tree into
`~/.doom.d`.

That config assumes the rest of this environment exists:

- `fd`, `rg`, and `git grep` for search
- `vterm` for project terminals
- `delta`, `magit`, and `diff-hl` for review
- language tools such as `prettier`, `uv`, `ruff`, `ty`, `taplo`,
  `rust-analyzer`, and the `.NET` CLI

The result is a workflow where Emacs assembles context and terminals do the
execution.

## Core Workflow

### Search and Navigation

- `C-s`: `consult-line`
- `C-x b`: `consult-buffer`
- `SPC f d`: project file search with `fd`
- `SPC s g`: project ripgrep
- `SPC s G`: project `git grep`
- `SPC s i`: imenu

### Agent and Project Terminals

- `SPC o t`: plain project terminal
- `SPC o c`: project Codex terminal
- `SPC o a`: project Claude terminal
- `SPC o C`: project GitHub Copilot terminal
- `SPC o T`: test command
- `SPC o b`: build command
- `SPC o R`: run command
- `SPC o L`: lint command

### Notes

- `SPC n p`: open project notes
- `SPC n t`: capture TODO
- `SPC n f`: capture finding
- `SPC n x`: capture current code context

Project notes are stored under:

```text
~/org/projects/<project>.org
```

### Review

- `SPC g g`: Magit status
- `SPC g n`: next hunk
- `SPC g p`: previous hunk
- `SPC g s`: stage hunk
- `SPC g r`: revert hunk
- `SPC g b`: inspect hunk

### File References

- `SPC o .`: open a file reference at point
- `C-c C-o` in `vterm`: open a file reference from terminal output
- `SPC c p`: copy absolute file path
- `SPC c r`: copy project-relative path
- `SPC c l`: copy `path:line`

This is meant to make agent prompts and tool output easy to move back into
code.

## Repo-Local Command Defaults

Emacs reads a repo-local data file named:

```elisp
agent-workflow.el
```

That file is not executed. It is read as data and used to supply defaults for:

- test
- build
- run
- lint
- Codex
- Claude
- GitHub Copilot

See [agent-workflow.example.el](/Users/keegancaruso/source/bootstrap/agent-workflow.example.el).

## Language Support

This setup already includes editor support for:

- JavaScript, JSX, TypeScript, and TSX
- `.NET` and C#
- Python through `uv`, `ruff`, and `ty`
- Rust
- TOML
- shell, JSON, YAML, and Markdown

Language-specific commands live behind prefixes:

- `SPC o d`: `.NET`
- `SPC o p`: Python
- `SPC o r`: Rust

## Good Defaults for Daily Use

- Keep your repo-local command defaults in `agent-workflow.el`.
- Use Emacs for search, review, and note capture.
- Use Zellij or terminal tabs for longer interactive sessions.
- Rerun `doom sync` after changing packages or module declarations.
