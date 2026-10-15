#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_ROOT="$(mktemp -d)"
export XDG_STATE_HOME="${TEST_ROOT}/state"

cleanup() {
  local mount

  while IFS= read -r mount; do
    [[ -z "$mount" ]] || fusermount3 -u "$mount" 2>/dev/null || true
  done < <(findmnt -rn -t fuse.fuse-overlayfs -o TARGET | grep -F "${TEST_ROOT}/" || true)
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail_test() {
  printf 'Test failed: %s\n' "$*" >&2
  exit 1
}

repository="${TEST_ROOT}/repository"
mkdir -p "$repository"
git -C "$repository" init -q -b main
git -C "$repository" config user.name "nix-container-wt test"
git -C "$repository" config user.email "nix-container-wt@example.invalid"
printf 'base\n' >"${repository}/base.txt"
git -C "$repository" add base.txt
git -C "$repository" commit -q -m "Initial commit"

# shellcheck disable=SC2016
"${REPO_DIR}/nix-container-wt" experiment -C "$repository" -- \
  bash -euc '
    test "$PWD" = /workspace
    test "$HOME" = /home/dev
    test "$(id -u)" -ne 0
    terraform version
    printf "overlay\n" > overlay.txt
    printf "persistent\n" >"$HOME/persistent.txt"
  '

[[ ! -e "${repository}/overlay.txt" ]] \
  || fail_test "Container workspace write escaped the overlay."

# shellcheck disable=SC2016
"${REPO_DIR}/nix-container-wt" experiment -C "$repository" -- \
  bash -euc '
    test "$(<overlay.txt)" = overlay
    test "$(<"$HOME/persistent.txt")" = persistent
    printf "second run\n" >>"$HOME/persistent.txt"
  '

[[ ! -e "${repository}/overlay.txt" ]] \
  || fail_test "Reopened container workspace write escaped the overlay."

printf 'Nix workspace container checks passed\n'
