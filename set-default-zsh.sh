#!/usr/bin/env bash
set -euo pipefail

SHELLS_FILE="${SHELLS_FILE:-/etc/shells}"

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
      local os_release="${OS_RELEASE_FILE:-/etc/os-release}"
      [[ -f "$os_release" ]] || fail "Unable to detect Linux distribution."
      # shellcheck disable=SC1090
      source "$os_release"
      case "${ID:-}" in
        ubuntu|fedora)
          OS="$ID"
          ;;
        *)
          fail "Unsupported Linux distribution: ${ID:-unknown}. This script supports Ubuntu and Fedora."
          ;;
      esac
      ;;
    *)
      fail "Unsupported operating system: $(uname -s)"
      ;;
  esac
}

set_default_zsh() {
  local zsh_path

  zsh_path="$(command -v zsh)" \
    || fail "zsh was not found. Install zsh first."

  if [[ "$OS" == "ubuntu" || "$OS" == "fedora" ]]; then
    if ! grep -Fxq "$zsh_path" "$SHELLS_FILE"; then
      printf '%s\n' "$zsh_path" | sudo tee -a "$SHELLS_FILE" >/dev/null
    fi
    if [[ "${SHELL:-}" != "$zsh_path" ]]; then
      command -v chsh >/dev/null 2>&1 \
        || fail "chsh is required to change the default shell."
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
