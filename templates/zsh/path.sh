typeset -U path PATH
_nix_bootstrap_profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/bootstrap"
path=("$_nix_bootstrap_profile/bin" "$HOME/.local/bin" $path)
unset _nix_bootstrap_profile
