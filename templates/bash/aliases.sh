# shellcheck shell=bash

for _brew_prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
  if [[ -x "$_brew_prefix/bin/brew" ]]; then
    export HOMEBREW_PREFIX="$_brew_prefix"
    export PATH="$_brew_prefix/bin:$_brew_prefix/sbin:$PATH"
    break
  fi
done
unset _brew_prefix

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
