# zsh-syntax-highlighting (must be sourced last)
if [[ -o interactive && -z "${ZSH_NONINTERACTIVE_SAFE:-}" ]]; then
  _nix_bootstrap_profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/bootstrap"
  for _zsh_syntax_highlighting in \
    "$_nix_bootstrap_profile/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  do
    if [[ -d "${_zsh_syntax_highlighting:h}/highlighters" ]]; then
      ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR="${_zsh_syntax_highlighting:h}/highlighters"
    fi
    if _zsh_cache_source "$_zsh_syntax_highlighting" zsh-syntax-highlighting; then
      break
    fi
  done
  unset _nix_bootstrap_profile _zsh_syntax_highlighting
fi

unfunction _zsh_cache_source _zsh_compile_file 2>/dev/null
unset _zsh_startup_cache_dir
