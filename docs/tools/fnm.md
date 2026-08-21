# fnm

`fnm` is a fast Node.js version manager.

The zsh setup keeps the default Node.js installation on `PATH`, but defers the
full `fnm env` initialization until the first Node-related command or until
entering a directory with `.node-version`, `.nvmrc`, or `package.json`.

## Common Commands

- `fnm install --lts`: install the current Node.js LTS
- `fnm use --lts`: use the current LTS in this shell
- `fnm default <version>`: set the default Node version
- `fnm list`: list installed Node versions
