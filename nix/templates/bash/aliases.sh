# shellcheck shell=bash

_nix_bootstrap_profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/bootstrap"
export PATH="$_nix_bootstrap_profile/bin:$HOME/.local/bin:$PATH"
unset _nix_bootstrap_profile

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
