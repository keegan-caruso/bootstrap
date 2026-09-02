typeset -U path PATH
export PATH="$HOME/.local/bin:$PATH"

for _brew_prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
  if [[ -x "$_brew_prefix/bin/brew" ]]; then
    export HOMEBREW_PREFIX="$_brew_prefix"
    path=("$_brew_prefix/bin" "$_brew_prefix/sbin" $path)
    break
  fi
done
unset _brew_prefix

if [[ -d "${DOTNET_ROOT:-$HOME/.dotnet}" ]]; then
  export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
  export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
fi

if [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
fi
