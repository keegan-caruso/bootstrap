#!/usr/bin/env bash

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] \
    || grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
}
