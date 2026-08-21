typeset -U path PATH
export PATH="$HOME/.local/bin:$PATH"

if [[ -d "${DOTNET_ROOT:-$HOME/.dotnet}" ]]; then
  export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
  export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
fi

if [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
fi
