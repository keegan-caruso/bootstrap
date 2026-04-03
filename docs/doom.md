# Doom Emacs

The tracked Doom config lives under `doom/` and is copied into `~/.doom.d`.

## Files

Top-level files:

- `doom/init.el`
- `doom/config.el`
- `doom/packages.el`

Split config files:

- `doom/config/core.el`
- `doom/config/javascript.el`
- `doom/config/dotnet.el`
- `doom/config/python.el`
- `doom/config/rust.el`
- `doom/config/toml.el`

## Editor Direction

This setup treats Emacs as a strong editor and review surface, not the main
terminal control plane.

It is optimized for:

- project navigation
- structured search
- Magit and diff review
- project-scoped notes
- launching agent and build/test terminals from the editor
- moving from terminal output back into source files quickly

## Core Completion and Search

The config uses:

- `vertico` for minibuffer candidate display
- `orderless` for matching behavior
- `consult` for file, buffer, line, and grep commands

Project-oriented commands include:

- `fd`-backed project file search
- `ripgrep` project search
- `git grep` project search

## Terminal Integration

The config uses `vterm`.

Core terminal commands:

- `SPC o t`: open a project terminal
- `SPC o c`: open a project Codex terminal
- `SPC o a`: open a project Claude terminal
- `SPC o C`: open a project GitHub Copilot terminal
- `SPC o T`: open a project test terminal
- `SPC o b`: open a project build terminal
- `SPC o R`: open a project run terminal
- `SPC o L`: open a project lint terminal
- `SPC o g`: open a project Git terminal running `git status`

## Notes and Capture

Project notes live under:

```text
~/org/projects/<project>.org
```

Built-in capture workflows include:

- TODOs
- findings
- scratch notes
- bug reports
- review notes
- implementation plans
- prompt drafts
- code-context captures

## Review and Git

The config uses:

- `magit`
- `diff-hl`

Review helpers include:

- hunk navigation
- hunk staging and reverting
- current-hunk inspection
- Magit status

## LSP and Formatting

The config prefers `eglot` over heavier LSP integration.

Formatting and linting are enabled where the tooling is predictable and fast
enough to be useful:

- shell: `shfmt`, `shellcheck`
- Markdown: `prettier`, `markdownlint-cli2`
- YAML: `prettier`, `yamllint`
- JSON: `prettier`
- JavaScript/TypeScript: `prettier`, ESLint
- Python: `ruff`, `ty`
- Rust: `rustfmt`, `rust-analyzer`
- TOML: `taplo`

## Package Additions

The tracked `doom/packages.el` adds:

- `consult`
- `diff-hl`
- `flymake-collection`
- `flymake-shellcheck`
- `orderless`
- `toml-mode`
