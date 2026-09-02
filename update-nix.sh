#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FLAKE_DIR="${SCRIPT_DIR}/nix"
FLAKE_URL="path:${FLAKE_DIR}"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
PROFILE_PATH="${STATE_HOME}/nix/profiles/bootstrap"
# shellcheck source=lib/platform.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/nix-profile.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/nix-profile.sh"

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
  local current_system
  local desired_attr
  local output_name
  local profile_entries
  local status=0

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
  output_name="$(nix_tool_output)"
  nix build --no-link "${FLAKE_URL}#${output_name}"

  [[ -e "$PROFILE_PATH" || -L "$PROFILE_PATH" ]] \
    || fail "Bootstrap profile not found at ${PROFILE_PATH}; run bootstrap-nix.sh first."

  (
    acquire_nix_profile_lock "$PROFILE_PATH"
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'status=$?; release_nix_profile_lock; exit "$status"' EXIT

    remove_abandoned_profile_staging "$PROFILE_PATH"
    current_system="$(nix eval --impure --raw --expr builtins.currentSystem)"
    desired_attr="packages.${current_system}.${output_name}"
    profile_entries="$(
      nix profile list --profile "$PROFILE_PATH" | awk '
        /^Flake attribute:/ { attr = $3 }
        /^Original flake URL:/ {
          url = $0
          sub(/^Original flake URL:[[:space:]]*/, "", url)
          print attr "\t" url
        }
      '
    )"
    if [[ "$profile_entries" != "${desired_attr}"$'\t'"${FLAKE_URL}" ]]; then
      fail "Bootstrap profile does not match ${FLAKE_URL}#${output_name}; rerun bootstrap-nix.sh."
    fi

    log "Atomically upgrading the bootstrap Nix profile"
    nix profile upgrade --profile "$PROFILE_PATH" --all
  )

  log "Update complete. Review and commit nix/flake.lock."
}

main "$@"
