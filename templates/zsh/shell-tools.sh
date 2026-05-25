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
    # Route xdg-open / $BROWSER at a real Windows browser binary when one is
    # available. wslview / wslu invoke explorer.exe directly, which — when the
    # WSL cwd is a Linux/UNC path — also pops a spurious Explorer window at
    # ~/Documents on the Windows side. Pointing at the browser .exe bypasses
    # explorer.exe entirely. Falls back to wslview if neither is installed.
    if [[ -x "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" ]]; then
      export BROWSER="/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
    elif [[ -x "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe" ]]; then
      export BROWSER="/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe"
    elif [[ -x "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" ]]; then
      export BROWSER="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
    elif command -v wslview >/dev/null 2>&1; then
      export BROWSER=wslview
    fi
  fi
fi
