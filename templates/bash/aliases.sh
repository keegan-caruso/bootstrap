# shellcheck shell=bash

export PATH="$HOME/.nix-profile/bin:$HOME/.local/bin:$PATH"

# Modern CLI aliases
alias grep='rg'
alias find='fd'
alias cat='bat'
alias ls='eza'
alias ll='eza -la'
alias lt='eza --tree'
alias df='duf'
alias du='dust'
alias top='btm'
alias ps='procs'
alias bench='hyperfine'
alias count='tokei'
alias http='xh'
alias dns='doggo'
