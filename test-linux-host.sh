#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FEDORA_IMAGE="${FEDORA_IMAGE:-registry.fedoraproject.org/fedora:45}"

fail_test() {
  printf 'Linux host test failed: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local expected="$1"
  local actual="$2"

  [[ "$actual" == *"$expected"* ]] \
    || fail_test "Expected output to contain: ${expected}"
}

if [[ "${1:-}" != "--inside-fedora" ]]; then
  (( $# == 0 )) || fail_test "Usage: ${0##*/}"

  if [[ "$(uname -s)" != "Linux" ]]; then
    printf 'Skipping Fedora host test outside Linux\n'
    exit 0
  fi

  if command -v podman >/dev/null 2>&1; then
    container_runtime="podman"
  elif command -v docker >/dev/null 2>&1; then
    container_runtime="docker"
  else
    fail_test "Podman or Docker is required to run the Fedora host test."
  fi

  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-fedora-test.XXXXXX")"
  storage_dir="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-fedora-storage.XXXXXX")"
  container_data_home="${storage_dir}/data"
  container_runtime_dir="${storage_dir}/run"
  # shellcheck disable=SC2329
  cleanup_staging() {
    if [[ "$container_runtime" == "podman" ]]; then
      XDG_DATA_HOME="$container_data_home" \
      XDG_RUNTIME_DIR="$container_runtime_dir" \
        podman unshare rm -rf -- "$storage_dir" 2>/dev/null || true
    fi
    rm -rf -- "$storage_dir"
    rm -rf -- "$staging_dir"
  }
  trap cleanup_staging EXIT
  mkdir -p "$staging_dir/lib" "$container_data_home" "$container_runtime_dir"
  chmod 700 "$container_runtime_dir"
  cp \
    "$REPO_DIR/bootstrap-nix.sh" \
    "$REPO_DIR/packages.sh" \
    "$REPO_DIR/set-default-zsh.sh" \
    "$REPO_DIR/test-linux-host.sh" \
    "$staging_dir/"
  cp -a "$REPO_DIR/lib/." "$staging_dir/lib/"

  cd /
  if [[ "$container_runtime" == "podman" ]]; then
    XDG_DATA_HOME="$container_data_home" \
    XDG_RUNTIME_DIR="$container_runtime_dir" \
      podman run \
        --rm \
        --pull=always \
        --security-opt label=disable \
        --volume "${staging_dir}:/workspace:ro" \
        --workdir /workspace \
        "$FEDORA_IMAGE" \
        bash ./test-linux-host.sh --inside-fedora
  else
    docker run \
      --rm \
      --pull=always \
      --security-opt label=disable \
      --volume "${staging_dir}:/workspace:ro" \
      --workdir /workspace \
      "$FEDORA_IMAGE" \
      bash ./test-linux-host.sh --inside-fedora
  fi
  exit
fi

(( $# == 1 )) || fail_test "Usage: ${0##*/} --inside-fedora"

# shellcheck source=bootstrap-nix.sh
# shellcheck disable=SC1091
source "${REPO_DIR}/bootstrap-nix.sh"

# The container inherits the WSL host kernel but represents a native Fedora
# userspace for these host-integration checks.
# shellcheck disable=SC2329
is_wsl() {
  return 1
}

# shellcheck disable=SC2329
sudo() {
  if [[ "${1:-}" == "-v" ]]; then
    return
  fi
  command "$@"
}

assert_detected_os() {
  local expected_os="$1"
  local id="$2"
  local version="$3"
  local os_release

  os_release="$(mktemp)"
  printf 'ID=%s\nVERSION_ID=%s\n' "$id" "$version" >"$os_release"
  (
    OS_RELEASE_FILE="$os_release" detect_os
    [[ "$OS" == "$expected_os" ]]
  ) || fail_test "Failed to detect ${id} ${version}"
  rm -f "$os_release"
}

assert_rejected_os() {
  local expected_error="$1"
  local id="$2"
  local version="$3"
  local os_release
  local output

  os_release="$(mktemp)"
  printf 'ID=%s\nVERSION_ID=%s\n' "$id" "$version" >"$os_release"
  if output="$(OS_RELEASE_FILE="$os_release" detect_os 2>&1)"; then
    rm -f "$os_release"
    fail_test "Unexpectedly accepted ${id} ${version}"
  fi
  rm -f "$os_release"
  assert_contains "$expected_error" "$output"
}

printf 'Testing Fedora and Ubuntu host detection\n'
assert_detected_os fedora fedora 45
assert_detected_os ubuntu ubuntu 24.04
assert_detected_os ubuntu ubuntu 26.04
assert_detected_os ubuntu ubuntu 26.10
assert_detected_os ubuntu ubuntu 25.10
assert_rejected_os "This script supports Fedora 45" fedora 44

printf 'Testing unsupported Fedora host variants\n'
touch /run/ostree-booted
if output="$(detect_os 2>&1)"; then
  rm -f /run/ostree-booted
  fail_test "Unexpectedly accepted a Fedora Atomic host"
fi
rm -f /run/ostree-booted
assert_contains "Fedora Atomic desktops are not supported" "$output"

# shellcheck disable=SC2329
is_wsl() {
  return 0
}
if output="$(detect_os 2>&1)"; then
  fail_test "Unexpectedly accepted Fedora on WSL"
fi
assert_contains "WSL bootstrap supports Ubuntu only" "$output"

# shellcheck disable=SC2329
is_wsl() {
  return 1
}
detect_os
[[ "$OS" == "fedora" ]] || fail_test "The Fedora container was not detected"

printf 'Testing Fedora host prerequisite installation\n'
require_sudo
dnf_log="$(mktemp)"
if ! install_host_prereqs >"$dnf_log" 2>&1; then
  cat "$dnf_log" >&2
  rm -f "$dnf_log"
  fail_test "Fedora host prerequisite installation failed"
fi
rm -f "$dnf_log"
test -x /usr/bin/curl
for package in \
  ca-certificates \
  gnome-keyring \
  libsecret \
  policycoreutils \
  util-linux \
  xz
do
  rpm -q "$package" >/dev/null \
    || fail_test "Fedora prerequisite package is not installed: ${package}"
done

printf 'Testing Fedora does not configure Ubuntu rootless prerequisites\n'
sudo() {
  fail_test "Fedora rootless setup unexpectedly invoked sudo: $*"
}
ensure_rootless_container_prereqs

printf 'Testing Fedora default-shell setup\n'
command dnf install -y zsh >/dev/null 2>&1
shells_file="$(mktemp)"
chsh_log="$(mktemp)"
SHELLS_FILE="$shells_file" \
CHSH_LOG="$chsh_log" \
SHELL=/bin/bash \
USER=fedora-test \
bash -euc '
  source "$1/set-default-zsh.sh"
  sudo() {
    command "$@"
  }
  chsh() {
    printf "%s\n" "$*" >>"$CHSH_LOG"
  }

  detect_os
  test "$OS" = fedora
  set_default_zsh
  grep -Fxq "$(command -v zsh)" "$SHELLS_FILE"
  grep -Fq -- "-s $(command -v zsh)" "$CHSH_LOG"
' fedora-shell-test "$REPO_DIR"
rm -f "$shells_file" "$chsh_log"

printf 'Fedora 45 host integration checks passed\n'
