# Workflows

## Agent Workflow Defaults

Repo-local workflow defaults live in a project-root file named:

```elisp
agent-workflow.el
```

The file is read as data only. It is not `load`ed or executed.

Expected shape:

```elisp
((commands .
  ((test . "pnpm test")
   (build . "pnpm build")
   (run . "pnpm dev")
   (lint . "pnpm lint")))
 (agents .
  ((codex . "codex")
   (claude . "claude")
   (gh-copilot . "gh copilot"))))
```

These defaults are used by the project terminal commands so common repos stop
prompting every time.

## Core Agent Commands

- `SPC o c`: Codex
- `SPC o a`: Claude
- `SPC o C`: GitHub Copilot

Each command opens a named `vterm` in the current project root and runs the
configured agent CLI.

## Shared Project Commands

- `SPC o T`: test
- `SPC o b`: build
- `SPC o R`: run
- `SPC o L`: lint
- `SPC o g`: `git status`

If `agent-workflow.el` provides a matching command, that value is used.
Otherwise the command prompts.

## Navigation Helpers

- `SPC o .`: open a file reference at point
- `C-c C-o` in `vterm`: open a file reference at point
- `SPC c p`: copy absolute file path
- `SPC c r`: copy project-relative file path
- `SPC c l`: copy `path:line`

Supported file references include:

- `path/to/file`
- `path/to/file:12`
- `path/to/file:12:3`

## Notes and Capture

Project notes commands:

- `SPC n p`: open project notes
- `SPC n t`: capture TODO
- `SPC n f`: capture finding
- `SPC n s`: capture scratch note
- `SPC n b`: capture bug report
- `SPC n r`: capture review note
- `SPC n i`: capture implementation plan
- `SPC n d`: capture prompt draft
- `SPC n x`: capture current code context

The code-context capture records the current project-relative file, current
line, and current symbol when available.

## Search and Review

Search:

- `C-s`: `consult-line`
- `C-x b`: `consult-buffer`
- `SPC f d`: project file search with `fd`
- `SPC s g`: project ripgrep
- `SPC s G`: project `git grep`
- `SPC s i`: imenu

Review:

- `SPC g g`: Magit status
- `SPC g n`: next hunk
- `SPC g p`: previous hunk
- `SPC g s`: stage current hunk
- `SPC g r`: revert current hunk
- `SPC g b`: inspect current hunk
