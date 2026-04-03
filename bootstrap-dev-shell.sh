#!/usr/bin/env bash
set -euo pipefail

GIT_NAME="Keegan Caruso"
SCRIPT_MARKER="codex-dev-shell"
IS_WSL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREW_PACKAGES=(
  fzf
  fd
  bat
  eza
  cmake
  cmark
  coreutils
  fontconfig
  git
  gh
  jj
  jq
  fnm
  markdownlint-cli2
  pandoc
  prettier
  yq
  yamllint
  ripgrep
  rust-analyzer
  eslint_d
  shellcheck
  shfmt
  duf
  dust
  bottom
  procs
  sd
  zoxide
  git-delta
  hyperfine
  tokei
  ncdu
  ruff
  taplo
  ty
  uv
  xh
  doggo
  xclip
  zellij
  starship
)
NPM_GLOBAL_PACKAGES=(
  typescript
  typescript-language-server
)

log() {
  printf '[setup] %s\n' "$*"
}

fail() {
  printf '[setup] %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

read_template() {
  local template_path="$1"

  if [[ ! -f "$template_path" ]]; then
    fail "Template not found: $template_path"
  fi

  cat "$template_path"
}

warn_if_slow_wsl_worktree() {
  if [[ "$IS_WSL" -eq 1 && "$PWD" == /mnt/* ]]; then
    log "WSL files under /mnt/* are slower than the Linux filesystem."
    log "For better performance, keep active repos under \$HOME or another native Linux path."
  fi
}

detect_os() {
  case "$(uname -s)" in
    Darwin)
      OS="macos"
      ;;
    Linux)
      if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        if [[ "${ID:-}" == "ubuntu" ]]; then
          OS="ubuntu"
          if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] || grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
            IS_WSL=1
          fi
        else
          fail "Unsupported Linux distribution: ${ID:-unknown}. This script supports Ubuntu only."
        fi
      else
        fail "Unable to detect Linux distribution."
      fi
      ;;
    *)
      fail "Unsupported operating system: $(uname -s)"
      ;;
  esac
}

require_sudo() {
  if [[ "$OS" == "ubuntu" ]]; then
    if ! command_exists sudo; then
      fail "sudo is required on Ubuntu."
    fi
    sudo -v
  fi
}

ensure_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file"
}

upsert_block() {
  local file="$1"
  local name="$2"
  local content="$3"
  local start="# >>> ${SCRIPT_MARKER}:${name}"
  local end="# <<< ${SCRIPT_MARKER}:${name}"
  local tmp

  ensure_file "$file"
  tmp="$(mktemp)"

  awk -v start="$start" -v end="$end" -v block="$content" '
    BEGIN {
      in_block = 0
      replaced = 0
    }
    $0 == start {
      print start
      print block
      print end
      in_block = 1
      replaced = 1
      next
    }
    $0 == end {
      in_block = 0
      next
    }
    !in_block {
      print
    }
    END {
      if (!replaced) {
        if (NR > 0) {
          print ""
        }
        print start
        print block
        print end
      }
    }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
}

append_unique_line() {
  local file="$1"
  local line="$2"
  ensure_file "$file"
  if ! grep -Fqx "$line" "$file"; then
    printf '%s\n' "$line" >>"$file"
  fi
}

install_ubuntu_base() {
  log "Installing Ubuntu base packages"
  sudo apt-get update
  sudo apt-get install -y build-essential procps curl file git zsh unzip fontconfig gpg
}

install_homebrew() {
  if command_exists brew; then
    return
  fi

  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

setup_brew_env() {
  if [[ "$OS" == "macos" ]]; then
    BREW_PREFIX="/opt/homebrew"
    if [[ ! -x "${BREW_PREFIX}/bin/brew" && -x "/usr/local/bin/brew" ]]; then
      BREW_PREFIX="/usr/local"
    fi
  else
    BREW_PREFIX="/home/linuxbrew/.linuxbrew"
  fi

  if [[ ! -x "${BREW_PREFIX}/bin/brew" ]]; then
    fail "Homebrew installation was not found at ${BREW_PREFIX}/bin/brew"
  fi

  eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
  append_unique_line "${HOME}/.zprofile" "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\""
}

install_symbola_font() {
  local font_url="https://raw.githubusercontent.com/ChiefMikeK/ttf-symbola/master/Symbola.ttf"
  local font_path

  if [[ "$OS" == "macos" ]]; then
    mkdir -p "${HOME}/Library/Fonts"
    font_path="${HOME}/Library/Fonts/Symbola.ttf"
  else
    mkdir -p "${HOME}/.local/share/fonts/Symbola"
    font_path="${HOME}/.local/share/fonts/Symbola/Symbola.ttf"
  fi

  log "Installing Symbola fallback font"
  curl -fsSL -o "$font_path" "$font_url"

  if command_exists fc-cache; then
    fc-cache -f "$(dirname "$font_path")" >/dev/null 2>&1 || true
  fi
}

install_brew_packages() {
  log "Installing CLI tools with Homebrew"
  brew install "${BREW_PACKAGES[@]}"

  if [[ "$OS" == "macos" ]]; then
    brew install --cask font-jetbrains-mono-nerd-font font-symbols-only-nerd-font
    install_symbola_font
    brew install --cask ghostty
  elif [[ "$OS" == "ubuntu" ]]; then
    mkdir -p "${HOME}/.local/share/fonts"
    curl -fsSL -o /tmp/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -o /tmp/JetBrainsMono.zip -d "${HOME}/.local/share/fonts/JetBrainsMonoNerdFont" >/dev/null
    curl -fsSL -o /tmp/NerdFontsSymbolsOnly.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
    unzip -o /tmp/NerdFontsSymbolsOnly.zip -d "${HOME}/.local/share/fonts/NerdFontsSymbolsOnly" >/dev/null
    install_symbola_font
    fc-cache -f "${HOME}/.local/share/fonts"
    if [[ "$IS_WSL" -eq 0 ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
    else
      log "Skipping Ghostty install under WSL"
    fi
  fi
}

install_node_with_fnm() {
  local node_version

  if ! command_exists fnm; then
    fail "fnm is required after installing Homebrew packages."
  fi

  eval "$(fnm env --use-on-cd --shell bash)"

  node_version="$(fnm current 2>/dev/null || true)"
  if [[ -z "$node_version" || "$node_version" == "system" ]]; then
    log "Installing Node.js LTS with fnm"
    fnm install --lts
    node_version="$(fnm current 2>/dev/null || true)"
  fi

  if [[ -z "$node_version" || "$node_version" == "system" ]]; then
    fail "fnm did not provide a managed Node.js runtime."
  fi

  fnm default "$node_version"
  fnm use "$node_version" >/dev/null

  if command_exists corepack; then
    log "Enabling Corepack"
    corepack enable
  fi
}

install_npm_global_packages() {
  install_node_with_fnm

  if ! command_exists npm; then
    fail "npm is required after installing Node.js with fnm."
  fi

  log "Installing fallback global npm packages"
  npm install -g "${NPM_GLOBAL_PACKAGES[@]}"
}

install_csharpier_if_dotnet_available() {
  if ! command_exists dotnet; then
    return
  fi

  log "Installing csharpier .NET tool"
  if dotnet tool update -g csharpier >/dev/null 2>&1 || dotnet tool install -g csharpier >/dev/null 2>&1; then
    mkdir -p "${HOME}/.local/bin"
    ln -sf "${HOME}/.dotnet/tools/csharpier" "${HOME}/.local/bin/csharpier"
  else
    log "Skipping csharpier: dotnet tool install failed"
  fi
}

install_wsl_vscode_launcher() {
  local local_bin="${HOME}/.local/bin"
  local code_wrapper="${local_bin}/code"
  local windows_code_path
  local windows_user_profile
  local wrapper_content

  windows_user_profile="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')"
  if [[ -n "$windows_user_profile" ]]; then
    windows_user_profile="/mnt/$(printf '%s' "$windows_user_profile" | sed 's#^\([A-Za-z]\):#\L\1#; s#\\#/#g')"
    windows_code_path="${windows_user_profile}/AppData/Local/Programs/Microsoft VS Code/bin/code"
  fi

  if [[ -z "${windows_code_path:-}" || ! -x "$windows_code_path" ]]; then
    windows_code_path="/mnt/c/Program Files/Microsoft VS Code/bin/code"
  fi

  if [[ ! -x "$windows_code_path" ]]; then
    fail "Visual Studio Code was not found on the Windows host. Install VS Code on Windows first or rerun this script outside WSL."
  fi

  wrapper_content=$(cat <<EOF
#!/usr/bin/env bash
exec "$windows_code_path" "\$@"
EOF
)

  upsert_block "$code_wrapper" "wrapper" "$wrapper_content"
  chmod +x "$code_wrapper"
}

install_vscode() {
  if command_exists code; then
    return
  fi

  log "Installing Visual Studio Code"

  if [[ "$OS" == "macos" ]]; then
    brew install --cask visual-studio-code
    return
  fi

  if [[ "$IS_WSL" -eq 1 ]]; then
    install_wsl_vscode_launcher
    return
  fi

  sudo mkdir -p /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/packages.microsoft.gpg ]]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null
    sudo chmod 0644 /etc/apt/keyrings/packages.microsoft.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    printf 'deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main\n' | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  fi

  sudo apt-get update
  sudo apt-get install -y code
}

write_doom_config() {
  local doom_config_dir="${HOME}/.doom.d"
  local source_dir="${SCRIPT_DIR}/doom"
  local source_file
  local relative_path

  mkdir -p "$doom_config_dir"
  if [[ ! -f "${source_dir}/init.el" || ! -f "${source_dir}/config.el" || ! -f "${source_dir}/packages.el" ]]; then
    fail "Doom config templates were not found in ${source_dir}"
  fi

  while IFS= read -r source_file; do
    relative_path="${source_file#${source_dir}/}"
    mkdir -p "$(dirname "${doom_config_dir}/${relative_path}")"
    install -m 0644 "${source_file}" "${doom_config_dir}/${relative_path}"
  done < <(find "${source_dir}" -type f)
}

install_doom_emacs() {
  local emacs_dir="${HOME}/.emacs.d"
  local doom_repo="https://github.com/doomemacs/doomemacs"

  log "Installing Emacs and Doom Emacs"

  if [[ "$OS" == "macos" ]]; then
    brew tap d12frosted/emacs-plus
    brew install --cask emacs-plus-app
  elif [[ "$OS" == "ubuntu" ]]; then
    brew install emacs
  fi

  if [[ -e "$emacs_dir" && ! -d "${emacs_dir}/.git" ]]; then
    fail "${emacs_dir} already exists and is not a Git checkout. Move it aside before running this script."
  fi

  if [[ -d "${emacs_dir}/.git" ]]; then
    local current_remote
    current_remote="$(git -C "$emacs_dir" remote get-url origin 2>/dev/null || true)"
    if [[ "$current_remote" != "$doom_repo" ]]; then
      fail "${emacs_dir} already exists and is not the Doom Emacs repository. Move it aside before running this script."
    fi
    git -C "$emacs_dir" pull --ff-only
  else
    git clone --depth 1 "$doom_repo" "$emacs_dir"
  fi

  write_doom_config

  if [[ -f "${HOME}/.spacemacs" ]]; then
    log "Existing ~/.spacemacs detected; Doom Emacs will use ~/.doom.d instead."
  fi

  YES=1 "${emacs_dir}/bin/doom" install --force
}

set_default_zsh() {
  local zsh_path

  zsh_path="$(command -v zsh)"
  if [[ -z "$zsh_path" ]]; then
    fail "zsh was not found after installation."
  fi

  if [[ "$OS" == "ubuntu" ]]; then
    if ! grep -Fxq "$zsh_path" /etc/shells; then
      printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    fi
    if [[ "$IS_WSL" -eq 1 ]]; then
      log "Skipping login shell change under WSL"
    elif [[ "${SHELL:-}" != "$zsh_path" ]]; then
      log "Setting zsh as the default shell for ${USER}"
      chsh -s "$zsh_path"
    fi
  fi
}

prompt_for_git_email() {
  local input

  while true; do
    read -r -p "GitHub email: " input
    if [[ -n "$input" ]]; then
      GIT_EMAIL="$input"
      return
    fi
    printf 'Email is required.\n'
  done
}

write_zshrc_blocks() {
  local zshrc="${HOME}/.zshrc"
  local local_bin_block
  local prompt_block
  local shell_block

  local_bin_block="$(read_template "${SCRIPT_DIR}/templates/zsh/path.sh")"
  prompt_block="$(read_template "${SCRIPT_DIR}/templates/zsh/prompt.sh")"
  shell_block="$(read_template "${SCRIPT_DIR}/templates/zsh/shell-tools.sh")"

  upsert_block "$zshrc" "path" "$local_bin_block"
  upsert_block "$zshrc" "prompt" "$prompt_block"
  upsert_block "$zshrc" "shell-tools" "$shell_block"
}

write_bashrc_wsl_block() {
  local bashrc="${HOME}/.bashrc"
  local wsl_block

  wsl_block="$(read_template "${SCRIPT_DIR}/templates/bash/wsl-zsh-handoff.sh")"

  upsert_block "$bashrc" "wsl-zsh-handoff" "$wsl_block"
}

write_starship_config() {
  local starship_config="${HOME}/.config/starship.toml"
  upsert_block "$starship_config" "config" "$(read_template "${SCRIPT_DIR}/templates/starship.toml")"
}

write_ghostty_config() {
  local ghostty_config="${HOME}/.config/ghostty/config"
  upsert_block "$ghostty_config" "config" "$(read_template "${SCRIPT_DIR}/templates/ghostty/config")"
}

write_jj_config() {
  local jj_config="${HOME}/.config/jj/config.toml"
  local jj_block

  jj_block="$(awk -v git_name="$GIT_NAME" -v git_email="$GIT_EMAIL" '
    {
      gsub(/__GIT_NAME__/, git_name)
      gsub(/__GIT_EMAIL__/, git_email)
      print
    }
  ' "${SCRIPT_DIR}/templates/jj/config.toml.tmpl")"

  upsert_block "$jj_config" "config" "$jj_block"
}

configure_git() {
  log "Configuring global Git settings"
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.light true
  git config --global delta.navigate true
  git config --global delta.line-numbers true
  git config --global delta.side-by-side true
  git config --global merge.conflictStyle zdiff3
  git config --global fetch.prune true
  git config --global init.defaultBranch main

  if [[ "$IS_WSL" -eq 1 ]]; then
    git config --global core.fileMode false
    git config --global core.autocrlf input
    if command_exists git-credential-manager; then
      git config --global credential.helper manager-core
    elif command_exists git-credential-manager-core; then
      git config --global credential.helper manager-core
    fi
  fi
}

main() {
  detect_os
  warn_if_slow_wsl_worktree
  require_sudo

  if [[ "$OS" == "ubuntu" ]]; then
    install_ubuntu_base
  fi

  install_homebrew
  setup_brew_env
  install_brew_packages
  install_npm_global_packages
  install_csharpier_if_dotnet_available
  install_vscode
  install_doom_emacs
  set_default_zsh
  prompt_for_git_email
  write_zshrc_blocks
  if [[ "$IS_WSL" -eq 1 ]]; then
    write_bashrc_wsl_block
  fi
  write_starship_config
  if [[ "$OS" == "macos" || "$IS_WSL" -eq 0 ]]; then
    write_ghostty_config
  fi
  configure_git
  write_jj_config

  log "Bootstrap complete"
  log "Open a new shell or run: source ~/.zshrc"
  if [[ "$OS" == "ubuntu" ]]; then
    if [[ "$IS_WSL" -eq 1 ]]; then
      log "WSL detected: Ghostty and login-shell changes were skipped."
      log "If VS Code is installed on Windows, the script added a ~/.local/bin/code launcher for it."
    else
      log "If your login shell was changed to zsh, it will apply to new sessions."
    fi
  fi
}

main "$@"
