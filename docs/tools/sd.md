# sd

`sd` is a simpler, regex-friendly replacement for `sed`.

## Common Commands

- `sd foo bar file.txt`: replace text in one file
- `sd 'foo\\d+' bar file.txt`: use a regex pattern
- `rg old -l | xargs sd old new`: batch-replace across files
