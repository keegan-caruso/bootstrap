# jj

`jj` is Jujutsu, a version control system with strong Git interop.

## Common Commands

- `jj st`: show working-copy status
- `jj log`: show commit history
- `jj commit -m "msg"`: create a commit
- `jj git push`: push through the Git remote

The managed Jujutsu configuration uses
`working-copy.eol-conversion = "input"`, matching WSL's
`git core.autocrlf=input`. This prevents CRLF-only working-copy changes while
keeping repository blobs normalized to LF. Jujutsu does not currently honor
per-file `.gitattributes` EOL rules.
