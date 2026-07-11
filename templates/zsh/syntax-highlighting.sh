# zsh-syntax-highlighting (must be sourced last)
if [[ -o interactive && -z "${ZSH_NONINTERACTIVE_SAFE:-}" ]]; then
  for _zsh_syntax_highlighting in \
    "${HOMEBREW_PREFIX:-}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "$HOME/.nix-profile/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  do
    if [[ -f "$_zsh_syntax_highlighting" ]]; then
      source "$_zsh_syntax_highlighting"
      break
    fi
  done
  unset _zsh_syntax_highlighting
fi
