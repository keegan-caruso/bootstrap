# fnm
_fnm_binary="$(command -v fnm 2>/dev/null)"
if [[ -n "$_fnm_binary" ]]; then
  export FNM_DIR="${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
  if [[ -d "$FNM_DIR/aliases/default/bin" ]]; then
    export PATH="$FNM_DIR/aliases/default/bin:$PATH"
  fi

  _fnm_lazy_commands=(
    fnm node npm npx corepack pnpm pnpx yarn yarnpkg
    tsc typescript-language-server
    markdownlint-cli2 oxfmt oxlint
  )

  _fnm_define_lazy_wrappers() {
    local command_name
    for command_name in "${_fnm_lazy_commands[@]}"; do
      functions[$command_name]='_fnm_lazy_load || return; command '"$command_name"' "$@"'
    done
  }

  _fnm_env() {
    if [[ -n "${XDG_RUNTIME_DIR:-}" &&
          ( ! -d "$XDG_RUNTIME_DIR" || ! -w "$XDG_RUNTIME_DIR" ) ]]; then
      env -u XDG_RUNTIME_DIR "$_fnm_binary" env --use-on-cd --shell zsh
    else
      "$_fnm_binary" env --use-on-cd --shell zsh
    fi
  }

  _fnm_lazy_chpwd() {
    if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
      _fnm_lazy_load
    fi
  }

  _fnm_lazy_load() {
    local command_name init

    if ! init="$(_fnm_env)"; then
      print -u2 "fnm: failed to initialize"
      return 1
    fi

    for command_name in "${_fnm_lazy_commands[@]}"; do
      unfunction "$command_name" 2>/dev/null
    done
    autoload -Uz add-zsh-hook
    add-zsh-hook -d chpwd _fnm_lazy_chpwd 2>/dev/null

    if ! eval "$init"; then
      print -u2 "fnm: failed to apply its shell environment"
      _fnm_define_lazy_wrappers
      add-zsh-hook chpwd _fnm_lazy_chpwd
      return 1
    fi

    unfunction _fnm_define_lazy_wrappers _fnm_env _fnm_lazy_chpwd
    unfunction _fnm_lazy_load
    unset _fnm_binary _fnm_lazy_commands
  }

  _fnm_define_lazy_wrappers
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _fnm_lazy_chpwd
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
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --preview '\''if [[ -d {} ]]; then eza --tree --level=2 --color=always {}; else bat --theme=GitHub --style=numbers --color=always --line-range :200 {}; fi'\'''

if [[ -f "$HOME/.nix-profile/share/fzf/key-bindings.zsh" ]]; then
  _zsh_cache_source "$HOME/.nix-profile/share/fzf/key-bindings.zsh" fzf-key-bindings
fi

if [[ -f "$HOME/.nix-profile/share/fzf/completion.zsh" ]]; then
  _zsh_cache_source "$HOME/.nix-profile/share/fzf/completion.zsh" fzf-completion
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
    # Provisioned by ~/bootstrap so shell startup only selects the browser.
    _wsl_browser="$HOME/.local/bin/wsl-browser"
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
