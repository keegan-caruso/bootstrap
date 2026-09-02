#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_ROOT="$(mktemp -d)"
export HOME="${TEST_ROOT}/home"
export XDG_STATE_HOME="${TEST_ROOT}/state"
mkdir -p "$HOME"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

# shellcheck source=bootstrap-nix.sh
# shellcheck disable=SC1091
source "${REPO_DIR}/bootstrap-nix.sh"

fail_test() {
  printf 'Test failed: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local expected="$1"
  local file="$2"

  grep -Fq "$expected" "$file" \
    || fail_test "Expected ${file} to contain: ${expected}"
}

assert_not_contains() {
  local unexpected="$1"
  local file="$2"

  if grep -Fq "$unexpected" "$file"; then
    fail_test "Expected ${file} not to contain: ${unexpected}"
  fi
}

assert_marker_once() {
  local marker="$1"
  local file="$2"
  local count

  count="$(grep -Fxc "$marker" "$file" || true)"
  [[ "$count" == "1" ]] \
    || fail_test "Expected one ${marker} marker in ${file}, found ${count}"
}

test_managed_config_is_idempotent() {
  local first_run="${TEST_ROOT}/first-run"

  cat >"${HOME}/.zprofile" <<EOF
keep-before
# >>> ${SCRIPT_MARKER}:homebrew
eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# <<< ${SCRIPT_MARKER}:homebrew
keep-after
EOF

  IS_WSL=0
  remove_homebrew_shell_config
  write_zshenv_block
  write_zshrc_blocks
  write_starship_config
  write_ghostty_config

  assert_contains "keep-before" "${HOME}/.zprofile"
  assert_contains "keep-after" "${HOME}/.zprofile"
  assert_not_contains "${SCRIPT_MARKER}:homebrew" "${HOME}/.zprofile"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:startup" "${HOME}/.zshenv"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:path" "${HOME}/.zshrc"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:config" "${HOME}/.config/starship.toml"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:config" "${HOME}/.config/ghostty/config"

  cp -R "$HOME" "$first_run"

  remove_homebrew_shell_config
  write_zshenv_block
  write_zshrc_blocks
  write_starship_config
  write_ghostty_config

  diff -ru "$first_run" "$HOME" \
    || fail_test "Managed configuration changed on the second run"

  IS_WSL=1
  write_bashrc_blocks
  write_bashrc_blocks
  assert_marker_once "# >>> ${SCRIPT_MARKER}:aliases" "${HOME}/.bashrc"
}

test_npm_registry_override() {
  local npm_log="${TEST_ROOT}/npm.log"

  fnm() {
    case "${1:-}" in
      env)
        return
        ;;
      current)
        printf 'v22.18.0\n'
        ;;
      default|use)
        return
        ;;
      *)
        fail_test "Unexpected fnm command: $*"
        ;;
    esac
  }

  corepack() {
    [[ "$*" == "enable" ]] || fail_test "Unexpected corepack command: $*"
  }

  npm() {
    if [[ "$*" == "config get registry" ]]; then
      printf '%s\n' "${NPM_CONFIG_REGISTRY:-https://registry.npmjs.org/}"
      printf 'registry=%s\n' "${NPM_CONFIG_REGISTRY:-}" >>"$npm_log"
      return
    fi

    printf 'npm %s\n' "$*" >>"$npm_log"
  }

  unset NPM_CONFIG_REGISTRY
  BOOTSTRAP_NPM_REGISTRY="https://registry.example.test/" install_node_tools

  assert_contains "registry=https://registry.example.test/" "$npm_log"
  assert_contains "npm uninstall -g typescript-language-server" "$npm_log"
  assert_contains "npm install -g ${NPM_GLOBAL_PACKAGES[*]}" "$npm_log"
  [[ -x "${HOME}/.local/bin/typescript-language-server" ]] \
    || fail_test "TypeScript language server wrapper was not installed"
}

test_platform_output_selection() {
  local command_log="${TEST_ROOT}/nix.log"

  nix() {
    if [[ "${1:-}" == "eval" ]]; then
      printf 'x86_64-linux'
      return
    fi

    printf 'nix %s\n' "$*" >>"$command_log"
  }

  update_dev_tools_profile() {
    printf 'profile %s\n' "$*" >>"$command_log"
  }

  IS_WSL=1
  install_dev_tools
  assert_contains "nix build --no-link ${PROFILE_REF}" "$command_log"
  assert_contains "profile ${PROFILE_REF} packages.x86_64-linux.default" "$command_log"

  : >"$command_log"
  IS_WSL=0
  install_dev_tools
  assert_contains "nix build --no-link ${WORKSTATION_PROFILE_REF}" "$command_log"
  assert_contains \
    "profile ${WORKSTATION_PROFILE_REF} packages.x86_64-linux.workstation" \
    "$command_log"
}

test_managed_config_is_idempotent
test_npm_registry_override
test_platform_output_selection

printf 'Bootstrap integration checks passed\n'
