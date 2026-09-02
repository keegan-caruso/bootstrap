_zsh_startup_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/startup"

_zsh_compile_file() {
  local file="$1"

  [[ -s "$file" ]] || return 1
  if [[ ! -s "${file}.zwc" || "$file" -nt "${file}.zwc" ]]; then
    if ! zcompile "$file"; then
      print -u2 "zsh: failed to compile startup cache: $file"
      return 1
    fi
  fi
}

_zsh_cache_source() {
  local source_file="$1"
  local cache_name="$2"
  local cache_dir="${_zsh_startup_cache_dir}/${cache_name}"
  local cache_file="${cache_dir}/${source_file:t}"
  local temp_file="${cache_file}.$$"
  local companion

  [[ -r "$source_file" ]] || return 1

  if [[ ! -s "$cache_file" || "$source_file" -nt "$cache_file" ]]; then
    if ! command mkdir -p "$cache_dir"; then
      print -u2 "zsh: failed to create startup cache directory"
      source "$source_file"
      return
    fi
    if ! command cp "$source_file" "$temp_file" ||
       ! command mv -f "$temp_file" "$cache_file"; then
      print -u2 "zsh: failed to cache startup file: $source_file"
      command rm -f "$temp_file"
      source "$source_file"
      return
    fi
  fi

  for companion in .version .revision-hash; do
    if [[ -r "${source_file:h}/$companion" &&
          ( ! -s "$cache_dir/$companion" ||
            "${source_file:h}/$companion" -nt "$cache_dir/$companion" ) ]]; then
      if ! command cp "${source_file:h}/$companion" "$cache_dir/$companion"; then
        print -u2 "zsh: failed to cache plugin metadata: ${source_file:h}/$companion"
      fi
    fi
  done

  _zsh_compile_file "$cache_file"
  source "$cache_file"
}

# GitHub CLI completions
_gh_command="$(command -v gh 2>/dev/null)"
_gh_completion_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"
_gh_completion_file="$_gh_completion_dir/_gh"
_gh_completion_identity_file="${_gh_completion_file}.command"
_gh_command_identity="${_gh_command:A}"
_gh_cached_identity=""
if [[ -r "$_gh_completion_identity_file" ]]; then
  _gh_cached_identity="$(<"$_gh_completion_identity_file")"
fi
if [[ -n "$_gh_command" ]] &&
   [[ ! -s "$_gh_completion_file" ||
      "$_gh_command_identity" != "$_gh_cached_identity" ||
      "$_gh_command" -nt "$_gh_completion_file" ]]; then
  if command mkdir -p "$_gh_completion_dir"; then
    _gh_completion_temp="${_gh_completion_file}.$$"
    _gh_identity_temp="${_gh_completion_identity_file}.$$"
    if "$_gh_command" completion -s zsh >| "$_gh_completion_temp" &&
       print -r -- "$_gh_command_identity" >| "$_gh_identity_temp" &&
       command mv -f "$_gh_completion_temp" "$_gh_completion_file" &&
       command mv -f "$_gh_identity_temp" "$_gh_completion_identity_file"; then
      :
    else
      print -u2 "zsh: failed to refresh GitHub CLI completions"
      command rm -f "$_gh_completion_temp" "$_gh_identity_temp"
    fi
    unset _gh_completion_temp _gh_identity_temp
  else
    print -u2 "zsh: failed to create the GitHub CLI completion cache"
  fi
fi
if [[ -s "$_gh_completion_file" ]]; then
  fpath=("$_gh_completion_dir" $fpath)
fi

# history
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

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
  _zsh_compile_file "${ZDOTDIR:-$HOME}/.zcompdump"
  zstyle ':completion:*' menu select
  zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

  # zsh-autosuggestions
  for _zsh_autosuggestions in \
    "$HOME/.nix-profile/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  do
    if _zsh_cache_source "$_zsh_autosuggestions" zsh-autosuggestions; then
      break
    fi
  done
  unset _zsh_autosuggestions

  if [[ -n "$_gh_command" && -s "$_gh_completion_file" ]]; then
    _zsh_compile_file "$_gh_completion_file"
    autoload -Uz _gh
    compdef _gh gh
  fi
fi

unset _gh_cached_identity _gh_command _gh_command_identity
unset _gh_completion_dir _gh_completion_file _gh_completion_identity_file
