if [[ -n "${WSL_DISTRO_NAME:-}" && $- == *i* ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${ZSH_VERSION:-}" ]]; then
  exec zsh
fi
