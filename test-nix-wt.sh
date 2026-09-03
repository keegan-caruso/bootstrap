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

create_git_repository() {
  local repository="$1"

  mkdir -p "$repository"
  git -C "$repository" init -q -b main
  git -C "$repository" config user.name "nix-wt test"
  git -C "$repository" config user.email "nix-wt-test@example.invalid"
  printf 'base\n' >"${repository}/base.txt"
  git -C "$repository" add base.txt
  git -C "$repository" commit -q -m "Initial commit"
}

advance_repository() {
  local repository="$1"

  printf 'new main\n' >"${repository}/new-main.txt"
  git -C "$repository" add new-main.txt
  git -C "$repository" commit -q -m "Advance main"
}

assert_no_test_mounts() {
  if findmnt -rn -t fuse.fuse-overlayfs -o TARGET | grep -Fq "${TEST_ROOT}/"; then
    fail_test "A test overlay remained mounted."
  fi
}

test_git_overlay_uses_immutable_lower() {
  local repository="${TEST_ROOT}/git-repo"
  local lower="${repository}.worktrees/nix-wt-git-test"

  create_git_repository "$repository"
  NIX_WT_IN_NIX=1 "${REPO_DIR}/nix-wt" git-test -C "$repository" -- \
    bash -lc 'printf "overlay\n" > overlay.txt'
  advance_repository "$repository"
  NIX_WT_IN_NIX=1 "${REPO_DIR}/nix-wt" git-test -C "$repository" -- \
    bash -lc 'test -f overlay.txt && test ! -e new-main.txt'

  [[ -d "$lower/.git" ]] \
    || fail_test "Git overlay lower clone was not created."
  [[ "$(git -C "$lower" rev-parse HEAD)" != "$(git -C "$repository" rev-parse HEAD)" ]] \
    || fail_test "Git overlay lower clone advanced with the source repository."
  assert_no_test_mounts
}

test_jj_overlay_uses_isolated_metadata() {
  local repository="${TEST_ROOT}/jj-repo"
  local lower="${repository}.worktrees/nix-wt-jj-test"

  create_git_repository "$repository"
  jj git init --colocate "$repository" >/dev/null
  NIX_WT_IN_NIX=1 "${REPO_DIR}/nix-wt" jj-test -C "$repository" -- \
    bash -lc '
      jj st >/dev/null
      printf "overlay\n" > overlay.txt
      jj describe -m "Test overlay"
      jj new -m "Second test commit"
    '
  advance_repository "$repository"
  jj -R "$repository" st >/dev/null
  # shellcheck disable=SC2016
  NIX_WT_IN_NIX=1 "${REPO_DIR}/nix-wt" jj-test -C "$repository" -- \
    bash -lc '
      jj st >/dev/null
      test -f overlay.txt
      test ! -e new-main.txt
      test "$(jj log -r @ --no-graph -T change_id)" = \
        "$(jj log -r user/keegancaruso/jj-test --no-graph -T change_id)"
    '

  [[ -d "$lower/.git" && -d "$lower/.jj" ]] \
    || fail_test "Jujutsu overlay lower clone lacks isolated VCS metadata."
  [[ "$(jj -R "$lower" workspace root)" == "$lower" ]] \
    || fail_test "Jujutsu lower clone does not own its workspace metadata."
  assert_no_test_mounts
}

test_git_overlay_uses_immutable_lower
test_jj_overlay_uses_isolated_metadata

printf 'nix-wt immutable lower checks passed\n'
