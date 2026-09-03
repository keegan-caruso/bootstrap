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

printf 'Testing Copilot sandbox configuration\n'
"${SCRIPT_DIR}/test-copilot-sandbox.sh"

printf 'Testing immutable overlay lower directories\n'
"${SCRIPT_DIR}/test-nix-wt.sh"

printf 'Checking Nix formatting\n'
(
  cd "$FLAKE_DIR"
  nix fmt -- --check flake.nix
)

printf 'Evaluating all supported Nix systems\n'
nix flake check --all-systems --no-build "path:${FLAKE_DIR}"

printf 'Building the current system tool environment\n'
nix build --no-link "path:${FLAKE_DIR}#$(nix_tool_output)"

if [[ "$(uname -s)" == "Linux" ]]; then
  printf 'Testing the Playwright browser environment\n'
  nix develop "path:${FLAKE_DIR}" --command playwright-run bash -c '
    test "$PLAYWRIGHT_BROWSERS_PATH" = "$HOME/.cache/ms-playwright"
    ldconfig -p | grep -q "libgbm.so.1"
    ldconfig -p | grep -q "libnss3.so"
  '
fi

printf 'Nix bootstrap checks passed\n'
