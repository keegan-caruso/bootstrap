#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${SCRIPT_DIR}/nix"
# shellcheck source=lib/platform.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/platform.sh"

log() {
  printf '[update-nix] %s\n' "$*"
}

fail() {
  printf '[update-nix] %s\n' "$*" >&2
  exit 1
}

activate_nix() {
  local nix_profile

  command -v nix >/dev/null 2>&1 && return

  for nix_profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  do
    if [[ -r "$nix_profile" ]]; then
      # shellcheck disable=SC1090
      source "$nix_profile"
      command -v nix >/dev/null 2>&1 && return
    fi
  done

  fail "Nix is not installed. Run ${SCRIPT_DIR}/bootstrap-nix.sh first."
}

main() {
  (( $# == 0 )) || fail "Usage: ${0##*/}"

  activate_nix

  [[ -f "${FLAKE_DIR}/flake.nix" ]] \
    || fail "Nix flake not found: ${FLAKE_DIR}/flake.nix"
  [[ -f "${FLAKE_DIR}/flake.lock" ]] \
    || fail "Nix lock file not found: ${FLAKE_DIR}/flake.lock"

  log "Updating the pinned nixpkgs revision"
  nix flake update --flake "$FLAKE_DIR"

  log "Checking the updated flake"
  nix flake check "path:${FLAKE_DIR}"

  log "Building the updated tool environment"
  if [[ "$(uname -s)" == "Linux" ]] && is_wsl; then
    nix build --no-link "path:${FLAKE_DIR}#default"
  else
    nix build --no-link "path:${FLAKE_DIR}#workstation"
  fi

  log "Upgrading installed profile entries from this flake"
  profile_entries="$(
    nix profile list --json \
      | jq -r --arg url "path:${FLAKE_DIR}" '
          .elements
          | to_entries[]
          | select(.value.originalUrl == $url)
          | .key
        '
  )"
  [[ -n "$profile_entries" ]] \
    || fail "No installed profile entry references ${FLAKE_DIR}; run bootstrap-nix.sh first."
  while IFS= read -r profile_entry; do
    nix profile upgrade "$profile_entry"
  done <<<"$profile_entries"

  log "Update complete. Review and commit nix/flake.lock."
}

main "$@"
