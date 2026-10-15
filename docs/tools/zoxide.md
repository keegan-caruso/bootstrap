# zoxide

`zoxide` is a smarter `cd` helper that learns your directory history.

## Common Commands

- `z repo-name`: jump to a frequently used directory
- `zi`: pick a directory interactively
- `zoxide query repo-name`: print the resolved path

In this setup, zoxide is always installed. Both the `starship` and `minimal`
Zsh profiles initialize directory tracking and expose `z` and `zi`. Changing
the prompt profile does not disable navigation or tracking.
