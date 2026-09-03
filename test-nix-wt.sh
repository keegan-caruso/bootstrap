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

test_legacy_overlay_migrates_without_losing_upper_work() {
  local repository="${TEST_ROOT}/legacy-repo"
  local overlay_name="legacy-test"
  local repo_id
  local state
  local lower
  local base_commit

  create_git_repository "$repository"
  base_commit="$(git -C "$repository" rev-parse HEAD)"
  repo_id="$(printf '%s' "$repository" | cksum | awk '{print $1}')"
  state="${XDG_STATE_HOME}/nix-wt/legacy-repo-${repo_id}/${overlay_name}"
  lower="${repository}.worktrees/nix-wt-${overlay_name}"
  mkdir -p "$state/upper" "$state/work" "$state/merged"
  printf '%s\n' "$repository" >"$state/repo-root"
  printf '%s\n' "$base_commit" >"$state/base-commit"
  printf 'preserved overlay work\n' >"$state/upper/overlay.txt"

  advance_repository "$repository"
  NIX_WT_IN_NIX=1 "${REPO_DIR}/nix-wt" "$overlay_name" -C "$repository" -- \
    bash -lc 'test "$(cat overlay.txt)" = "preserved overlay work" && test ! -e new-main.txt'

  [[ "$(cat "$state/lower-dir")" == "$lower" ]] \
    || fail_test "Legacy overlay migration recorded the wrong lower directory."
  [[ "$(cat "$state/vcs-mode")" == "git" ]] \
    || fail_test "Legacy overlay migration did not preserve Git mode."
  [[ "$(git -C "$lower" rev-parse HEAD)" == "$base_commit" ]] \
    || fail_test "Legacy overlay lower was not reconstructed at its recorded base."
  assert_no_test_mounts
}

test_interrupted_legacy_migration_resumes() {
  local repository="${TEST_ROOT}/interrupted-repo"
  local overlay_name="interrupted-test"
  local repo_id
  local state
  local lower
  local base_commit

  create_git_repository "$repository"
  base_commit="$(git -C "$repository" rev-parse HEAD)"
  repo_id="$(printf '%s' "$repository" | cksum | awk '{print $1}')"
  state="${XDG_STATE_HOME}/nix-wt/interrupted-repo-${repo_id}/${overlay_name}"
  lower="${repository}.worktrees/nix-wt-${overlay_name}"
  mkdir -p "$state/upper" "$state/work" "$state/merged" "$(dirname "$lower")"
  printf '%s\n' "$repository" >"$state/repo-root"
  printf '%s\n' "$base_commit" >"$state/base-commit"
  git clone -q --no-hardlinks "$repository" "$lower"
  git -C "$lower" checkout -q --detach "$base_commit"
  printf '%s\n' "$lower" >"$state/lower-dir"

  NIX_WT_IN_NIX=1 "${REPO_DIR}/nix-wt" "$overlay_name" -C "$repository" -- \
    bash -lc 'test -z "$(git status --short)"'

  [[ "$(cat "$state/vcs-mode")" == "git" ]] \
    || fail_test "Interrupted legacy migration did not complete VCS metadata."
  assert_no_test_mounts
}

test_legacy_jj_overlay_fails_before_migration() {
  local repository="${TEST_ROOT}/legacy-jj-repo"
  local overlay_name="legacy-jj-test"
  local repo_id
  local state
  local base_commit

  create_git_repository "$repository"
  base_commit="$(git -C "$repository" rev-parse HEAD)"
  repo_id="$(printf '%s' "$repository" | cksum | awk '{print $1}')"
  state="${XDG_STATE_HOME}/nix-wt/legacy-jj-repo-${repo_id}/${overlay_name}"
  mkdir -p "$state/upper/.jj/repo" "$state/work" "$state/merged"
  printf '%s\n' "$repository" >"$state/repo-root"
  printf '%s\n' "$base_commit" >"$state/base-commit"
  printf 'git\n' >"$state/upper/.jj/repo/type"

  if NIX_WT_IN_NIX=1 "${REPO_DIR}/nix-wt" "$overlay_name" -C "$repository" -- \
    true >/dev/null 2>&1
  then
    fail_test "Legacy Jujutsu overlay was migrated as Git."
  fi
  [[ ! -e "${repository}.worktrees/nix-wt-${overlay_name}" ]] \
    || fail_test "Legacy Jujutsu refusal created a lower directory."
  [[ ! -e "$state/lower-dir" && ! -e "$state/vcs-mode" ]] \
    || fail_test "Legacy Jujutsu refusal wrote migration metadata."
}

test_git_overlay_uses_immutable_lower
test_jj_overlay_uses_isolated_metadata
test_legacy_overlay_migrates_without_losing_upper_work
test_interrupted_legacy_migration_resumes
test_legacy_jj_overlay_fails_before_migration

printf 'nix-wt immutable lower checks passed\n'
