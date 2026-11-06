#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

awk '
  { sub(/\r$/, "") }
  /^\$linuxScript = @/ { capture = 1; next }
  capture && $0 == "\047@" { exit }
  capture { print }
' "$REPO_DIR/Mount-DataBtrfs.ps1" >"$TEST_ROOT/mount.sh"
test -s "$TEST_ROOT/mount.sh"
sh -n "$TEST_ROOT/mount.sh"

cat >"$TEST_ROOT/bin/findmnt" <<'SH'
#!/bin/sh
case "$*" in
    *--fstab*)
        [ "${MOCK_FSTAB_PRESENT:-1}" = 1 ] || exit 1
        case "$*" in
            *'--output SOURCE') printf '%s\n' "${MOCK_SOURCE:-UUID=test-uuid}" ;;
            *'--output FSTYPE') printf '%s\n' "${MOCK_FSTYPE:-btrfs}" ;;
            *'--output OPTIONS') printf '%s\n' "$MOCK_FSTAB_OPTIONS" ;;
            *) exit 1 ;;
        esac
        ;;
    *)
        [ "$MOCK_MOUNTED" = 1 ] || [ -f "$MOCK_STATE" ] || exit 1
        case "$*" in
            *'--output UUID') printf '%s\n' "${MOCK_ACTUAL_UUID:-test-uuid}" ;;
            *'--output FSTYPE') printf '%s\n' "${MOCK_ACTUAL_TYPE:-btrfs}" ;;
            *'--output OPTIONS') printf '%s\n' "$MOCK_ACTUAL_OPTIONS" ;;
            *'--output FSROOT') printf '%s\n' "$MOCK_ACTUAL_PATH" ;;
            *) printf 'mock mounted filesystem\n' ;;
        esac
        ;;
esac
SH
cat >"$TEST_ROOT/bin/blkid" <<'SH'
#!/bin/sh
if [ "$1" = -U ]; then
    [ "${MOCK_BLKID_STATUS:-0}" = 0 ] || exit "$MOCK_BLKID_STATUS"
    printf '/dev/mock\n'
else
    printf 'btrfs\n'
fi
SH
cat >"$TEST_ROOT/bin/btrfs" <<'SH'
#!/bin/sh
[ "${MOCK_DEFAULT_STATUS:-0}" = 0 ] || exit "$MOCK_DEFAULT_STATUS"
printf 'ID %s (FS_TREE)\n' "${MOCK_DEFAULT_ID:-5}"
SH
cat >"$TEST_ROOT/bin/systemctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$MOCK_LOG"
case "$1" in
    start)
        [ "$2" != mnt-data.mount ] || touch "$MOCK_STATE"
        ;;
    show) printf 'home-test-repos.mount unrelated.service\n' ;;
    *) exit 1 ;;
esac
SH
printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/modprobe"
printf '#!/bin/sh\nprintf "mnt-data.mount\\n"\n' >"$TEST_ROOT/bin/systemd-escape"
chmod +x "$TEST_ROOT/bin/"*

export MOCK_STATE="$TEST_ROOT/mounted"
export MOCK_LOG="$TEST_ROOT/systemctl.log"
export MOCK_MOUNTED=1
export MOCK_FSTAB_OPTIONS='subvolid=5,compress=zstd'
export MOCK_ACTUAL_OPTIONS='rw,subvolid=5,subvol=/'
export MOCK_ACTUAL_PATH=/

run_mount() {
  rm -f "$MOCK_STATE" "$MOCK_LOG"
  PATH="$TEST_ROOT/bin:$PATH" sh "$TEST_ROOT/mount.sh" "$1" /mnt/data \
    >"$TEST_ROOT/output" 2>"$TEST_ROOT/error"
}

expect_failure() {
  if run_mount "$1"; then
    printf 'Expected failure: %s\n' "$2" >&2
    exit 1
  fi
  grep -Fq -- "$2" "$TEST_ROOT/error"
}

expect_state() {
  run_mount check
  grep -Fxq "$1" "$TEST_ROOT/output"
}

expect_state mounted
MOCK_MOUNTED=0 expect_state attached
MOCK_MOUNTED=0 MOCK_BLKID_STATUS=2 expect_state detached
MOCK_MOUNTED=0 MOCK_BLKID_STATUS=1 expect_failure check 'blkid failed'
MOCK_FSTAB_PRESENT=0 expect_failure check 'No /etc/fstab entry'
MOCK_FSTYPE=ext4 expect_failure check 'is not Btrfs'
MOCK_SOURCE=/dev/mock expect_failure check 'must identify the filesystem by UUID'
MOCK_ACTUAL_UUID=wrong expect_failure check 'A different filesystem'
MOCK_ACTUAL_TYPE=ext4 expect_failure check 'is not Btrfs'
MOCK_ACTUAL_OPTIONS='rw,subvolid=256,subvol=/snapshot' \
  expect_failure check 'subvolid=5'
MOCK_FSTAB_OPTIONS='subvol=work' MOCK_ACTUAL_PATH=/snapshot \
  expect_failure check 'subvol=/work'
MOCK_FSTAB_OPTIONS='subvol=work/' MOCK_ACTUAL_PATH=/work expect_state mounted
MOCK_FSTAB_OPTIONS='subvol=/work\x20tree' MOCK_ACTUAL_PATH='/work\x20tree' \
  expect_state mounted
MOCK_FSTAB_OPTIONS='compress=zstd' expect_state mounted
MOCK_FSTAB_OPTIONS='compress=zstd' MOCK_DEFAULT_ID=256 \
  expect_failure check 'subvolid=256'
MOCK_FSTAB_OPTIONS='subvolid=0' MOCK_DEFAULT_ID=256 \
  MOCK_ACTUAL_OPTIONS='rw,subvolid=256,subvol=/work' expect_state mounted
MOCK_FSTAB_OPTIONS='compress=zstd' MOCK_DEFAULT_STATUS=1 \
  expect_failure check 'Cannot read the default'
MOCK_FSTAB_OPTIONS='subvol=work,subvolid=256' MOCK_ACTUAL_PATH=/work \
  expect_failure check 'subvolid=256'
test ! -e "$MOCK_LOG"

MOCK_MOUNTED=0 run_mount mount
grep -Fxq 'start mnt-data.mount' "$MOCK_LOG"
grep -Fxq 'start home-test-repos.mount' "$MOCK_LOG"
if grep -Fq unrelated.service "$MOCK_LOG"; then
  printf 'Started an unrelated service\n' >&2
  exit 1
fi
MOCK_MOUNTED=0 MOCK_ACTUAL_OPTIONS='rw,subvolid=256,subvol=/snapshot' \
  expect_failure mount 'subvolid=5'
if grep -Fq 'start home-test-repos.mount' "$MOCK_LOG"; then
  printf 'Started repository bind mount after subvolume mismatch\n' >&2
  exit 1
fi
run_mount mount
grep -Fxq 'start home-test-repos.mount' "$MOCK_LOG"

pwsh -NoLogo -NoProfile -File "$REPO_DIR/test-btrfs-startup.ps1"
printf 'Btrfs mount checks passed (mocked; no disks mounted or formatted)\n'
