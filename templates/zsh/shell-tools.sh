# fnm
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
  _fnm_current="$(fnm current 2>/dev/null || true)"
  if [[ -z "$_fnm_current" || "$_fnm_current" == "system" || "$_fnm_current" == "none" ]]; then
    if fnm install --lts >/dev/null 2>&1; then
      fnm default "$(fnm current)" >/dev/null 2>&1
      eval "$(fnm env --use-on-cd --shell zsh)"
    fi
  fi
  unset _fnm_current
fi

# zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# fzf
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
export BAT_THEME='GitHub'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --preview "bat --theme=GitHub --style=numbers --color=always --line-range :200 {}"'

if [[ -f "${HOMEBREW_PREFIX:-}/opt/fzf/shell/key-bindings.zsh" ]]; then
  source "${HOMEBREW_PREFIX}/opt/fzf/shell/key-bindings.zsh"
fi

if [[ -f "${HOMEBREW_PREFIX:-}/opt/fzf/shell/completion.zsh" ]]; then
  source "${HOMEBREW_PREFIX}/opt/fzf/shell/completion.zsh"
fi

if [[ -o interactive && -z "${ZSH_NONINTERACTIVE_SAFE:-}" ]]; then
  alias ff='fd --type f --hidden --exclude .git | fzf'
  alias vf='vim "$(fd --type f --hidden --exclude .git | fzf --preview "bat --theme=$BAT_THEME --style=numbers --color=always --line-range :200 {}")"'
  alias cdf='cd "$(fd --type d --hidden --exclude .git | fzf)"'

  # modern CLI aliases
  alias grep='rg'
  alias find='fd'
  alias cat='bat'
  alias ls='eza'
  alias ll='eza -la'
  alias lt='eza --tree'
  alias df='duf'
  alias du='dust'
  alias top='btm'
  alias ps='procs'
  alias bench='hyperfine'
  alias count='tokei'
  alias http='xh'
  alias dns='doggo'

  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    alias pbcopy='clip.exe'
    alias pbpaste='powershell.exe -NoProfile -Command Get-Clipboard'
    open() { explorer.exe "${1:-.}"; }
    # Route xdg-open / $BROWSER at a Windows browser binary via a wrapper.
    # Why a wrapper:
    #   1. wslu / wslview invoke explorer.exe directly, which (when the WSL
    #      cwd is a Linux/UNC path) pops a spurious Explorer window at
    #      ~/Documents on the Windows side.
    #   2. sensible-browser does `eval "$BROWSER \"$@\""`, so $BROWSER set
    #      to a path containing spaces or `(x86)` blows up with a syntax
    #      error and falls back to x-www-browser -> wslview anyway.
    # The wrapper has no spaces in its name and probes Edge -> Chrome ->
    # wslview internally. We also symlink it as `xdg-open` so .NET's
    # Process.Start(url, UseShellExecute=true) picks it up (it looks for
    # xdg-open / gnome-open / kfmclient on PATH; MSAL.NET uses this for
    # interactive auth).
    _wsl_browser="$HOME/.local/bin/wsl-browser"
    if [[ ! -x "$_wsl_browser" ]]; then
      mkdir -p "$HOME/.local/bin"
      cat > "$_wsl_browser" <<'WSL_BROWSER_EOF'
#!/bin/sh
# wsl-browser: open URLs in a Windows browser without going through
# explorer.exe. Managed by ~/bootstrap; safe to regenerate.
for candidate in \
  "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
  "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
do
  if [ -x "$candidate" ]; then
    exec "$candidate" "$@"
  fi
done
if command -v wslview >/dev/null 2>&1; then
  exec wslview "$@"
fi
echo "wsl-browser: no Windows browser found and wslview not installed" >&2
exit 127
WSL_BROWSER_EOF
      chmod +x "$_wsl_browser"
    fi
    if [[ -x "$_wsl_browser" ]] && [[ ! -e "$HOME/.local/bin/xdg-open" ]]; then
      ln -s "$_wsl_browser" "$HOME/.local/bin/xdg-open"
    fi
    if [[ -x "$_wsl_browser" ]]; then
      export BROWSER="$_wsl_browser"
    elif command -v wslview >/dev/null 2>&1; then
      export BROWSER=wslview
    fi
    unset _wsl_browser
    # artifacts-credprovider: disable the MSAL broker on WSL. The broker
    # bridges to Windows WAM via interop and inherits the Linux/UNC cwd,
    # popping Explorer at ~/Documents. With this off, MSAL falls back to
    # the system browser (via our xdg-open shim) or device code.
    export ARTIFACTS_CREDENTIALPROVIDER_MSAL_ALLOW_BROKER=false
  fi
fi
