#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${SCRIPT_DIR}/nix"
# shellcheck source=lib/platform.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/platform.sh"

if ! command -v nix >/dev/null 2>&1; then
  for nix_profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  do
    if [[ -r "$nix_profile" ]]; then
      # shellcheck disable=SC1090
      source "$nix_profile"
      break
    fi
  done
fi

command -v nix >/dev/null 2>&1 || {
  printf 'Nix is required\n' >&2
  exit 1
}

printf 'Testing bootstrap behavior with an isolated HOME\n'
"${SCRIPT_DIR}/test-bootstrap.sh"

printf 'Evaluating all supported Nix systems\n'
nix flake check --all-systems --no-build "path:${FLAKE_DIR}"

printf 'Building the current system tool environment\n'
if [[ "$(uname -s)" == "Linux" ]] && is_wsl; then
  nix build --no-link "path:${FLAKE_DIR}#default"
else
  nix build --no-link "path:${FLAKE_DIR}#workstation"
fi

printf 'Nix bootstrap checks passed\n'
