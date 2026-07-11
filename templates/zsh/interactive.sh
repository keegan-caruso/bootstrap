# history
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY

# key bindings
bindkey -e

# word navigation (Ctrl+Left / Ctrl+Right) across common terminal encodings
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[[1;3D' backward-word
bindkey '^[[5C'   forward-word
bindkey '^[[5D'   backward-word
bindkey '^[Oc'    forward-word
bindkey '^[Od'    backward-word
bindkey '^[f'     forward-word
bindkey '^[b'     backward-word

# word deletion (Ctrl+Backspace / Ctrl+Delete)
bindkey '^H'      backward-kill-word
bindkey '^[[3;5~' kill-word

# Home / End
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line
bindkey '^[[1~'   beginning-of-line
bindkey '^[[4~'   end-of-line
bindkey '^[OH'    beginning-of-line
bindkey '^[OF'    end-of-line

# Delete key
bindkey '^[[3~'   delete-char

# completion
if [[ -o interactive && -z "${ZSH_NONINTERACTIVE_SAFE:-}" ]]; then
  autoload -Uz compinit && compinit -C
  zstyle ':completion:*' menu select
  zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

  # zsh-autosuggestions
  for _zsh_autosuggestions in \
    "${HOMEBREW_PREFIX:-}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "$HOME/.nix-profile/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  do
    if [[ -f "$_zsh_autosuggestions" ]]; then
      source "$_zsh_autosuggestions"
      break
    fi
  done
  unset _zsh_autosuggestions
fi
