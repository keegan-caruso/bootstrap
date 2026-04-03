# delta

`delta` is a syntax-aware pager for diffs.

## Common Commands

- `git diff | delta`: view a diff with syntax highlighting
- `delta file.patch`: view a patch file
- `delta --side-by-side file.patch`: force side-by-side diff output

In this setup, Git is configured to use `delta` automatically.
