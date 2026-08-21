# starship
_starship_command="$(command -v starship 2>/dev/null)"
if [[ -n "$_starship_command" ]]; then
  _starship_cache_file="${_zsh_startup_cache_dir}/starship.zsh"
  _starship_identity_file="${_starship_cache_file}.command"
  _starship_command_identity="${_starship_command:A}"
  _starship_cached_identity=""
  if [[ -r "$_starship_identity_file" ]]; then
    _starship_cached_identity="$(<"$_starship_identity_file")"
  fi

  if [[ ! -s "$_starship_cache_file" ||
        "$_starship_command_identity" != "$_starship_cached_identity" ||
        "$_starship_command" -nt "$_starship_cache_file" ]]; then
    if command mkdir -p "$_zsh_startup_cache_dir"; then
      _starship_cache_temp="${_starship_cache_file}.$$"
      _starship_identity_temp="${_starship_identity_file}.$$"
      if "$_starship_command" init zsh >| "$_starship_cache_temp" &&
         print -r -- "$_starship_command_identity" >| "$_starship_identity_temp" &&
         command mv -f "$_starship_cache_temp" "$_starship_cache_file" &&
         command mv -f "$_starship_identity_temp" "$_starship_identity_file"; then
        :
      else
        print -u2 "zsh: failed to refresh the Starship startup cache"
        command rm -f "$_starship_cache_temp" "$_starship_identity_temp"
      fi
      unset _starship_cache_temp _starship_identity_temp
    else
      print -u2 "zsh: failed to create the Starship startup cache"
    fi
  fi

  if [[ -s "$_starship_cache_file" ]]; then
    _zsh_compile_file "$_starship_cache_file"
    source "$_starship_cache_file"
  fi
fi
unset _starship_cached_identity _starship_command _starship_command_identity
unset _starship_cache_file _starship_identity_file
