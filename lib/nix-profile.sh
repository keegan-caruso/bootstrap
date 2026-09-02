#!/usr/bin/env bash

acquire_nix_profile_lock() {
  local profile_path="$1"
  local lock_path="${profile_path}.bootstrap.lock"
  local lock_owner=""
  local stale_lock="${lock_path}.stale.$$"

  while ! ln -s "$$" "$lock_path" 2>/dev/null; do
    lock_owner="$(readlink "$lock_path" 2>/dev/null || true)"
    if [[ "$lock_owner" =~ ^[0-9]+$ ]] && kill -0 "$lock_owner" 2>/dev/null; then
      printf 'Nix profile update already running with PID %s\n' "$lock_owner" >&2
      return 1
    fi
    if mv "$lock_path" "$stale_lock" 2>/dev/null; then
      rm -f -- "$stale_lock"
    fi
    lock_owner=""
  done

  NIX_PROFILE_LOCK_PATH="$lock_path"
}

release_nix_profile_lock() {
  [[ -n "${NIX_PROFILE_LOCK_PATH:-}" ]] || return
  if [[ "$(readlink "$NIX_PROFILE_LOCK_PATH" 2>/dev/null || true)" == "$$" ]]; then
    rm -f -- "$NIX_PROFILE_LOCK_PATH"
  fi
  NIX_PROFILE_LOCK_PATH=""
}

remove_profile_links() {
  local profile_path="$1"
  local profile_link

  for profile_link in "$profile_path" "$profile_path"-*-link; do
    [[ -L "$profile_link" ]] || continue
    rm -f -- "$profile_link"
  done
}

remove_abandoned_profile_staging() {
  local profile_path="$1"
  local staging_link

  for staging_link in "${profile_path}.staging."*; do
    [[ -L "$staging_link" ]] || continue
    rm -f -- "$staging_link"
  done
}
