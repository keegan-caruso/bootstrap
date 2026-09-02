#!/usr/bin/env bash

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] \
    || grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
}

nix_tool_output() {
  local wsl_state="${1:-}"

  if [[ -z "$wsl_state" ]]; then
    if [[ "$(uname -s)" == "Linux" ]] && is_wsl; then
      wsl_state=1
    else
      wsl_state=0
    fi
  fi

  if [[ "$wsl_state" -eq 1 ]]; then
    printf 'default\n'
  else
    printf 'workstation\n'
  fi
}
