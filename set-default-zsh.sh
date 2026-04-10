#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[set-default-zsh] %s\n' "$*"
}

fail() {
  printf '[set-default-zsh] %s\n' "$*" >&2
  exit 1
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

set_default_zsh() {
  local zsh_path

  zsh_path="$(command -v zsh)"
  if [[ -z "$zsh_path" ]]; then
    fail "zsh was not found. Install zsh first."
  fi

  if [[ "$OS" == "ubuntu" ]]; then
    if ! grep -Fxq "$zsh_path" /etc/shells; then
      printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    fi
    if [[ "${SHELL:-}" != "$zsh_path" ]]; then
      log "Setting zsh as the default shell for ${USER}"
      chsh -s "$zsh_path"
    else
      log "zsh is already the default shell"
    fi
  fi
}

main() {
  detect_os
  set_default_zsh
  log "Done"
}

main "$@"
