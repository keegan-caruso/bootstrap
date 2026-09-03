typeset -U path PATH
_nix_bootstrap_profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/bootstrap"
path=("$_nix_bootstrap_profile/bin" "$HOME/.local/bin" $path)

if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]]; then
  path=("${(@)path:#/mnt/*/*Microsoft VS Code*/bin}")
fi

unset _nix_bootstrap_profile
