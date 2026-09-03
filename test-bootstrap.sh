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

assert_equals() {
  local expected="$1"
  local actual="$2"

  [[ "$actual" == "$expected" ]] \
    || fail_test "Expected '${expected}', found '${actual}'"
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
  install_copilot_instructions

  assert_contains "keep-before" "${HOME}/.zprofile"
  assert_contains "keep-after" "${HOME}/.zprofile"
  assert_not_contains "${SCRIPT_MARKER}:homebrew" "${HOME}/.zprofile"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:startup" "${HOME}/.zshenv"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:path" "${HOME}/.zshrc"
  assert_contains 'path=("${(@)path:#/mnt/*/*Microsoft VS Code*/bin}")' "${HOME}/.zshrc"
  assert_contains "artifacts-npm-credprovider markdownlint-cli2" "${HOME}/.zshrc"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:config" "${HOME}/.config/starship.toml"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:config" "${HOME}/.config/ghostty/config"
  assert_contains "playwright-run pnpm exec playwright test" \
    "${HOME}/.copilot/instructions/playwright.instructions.md"

  cp -R "$HOME" "$first_run"

  remove_homebrew_shell_config
  write_zshenv_block
  write_zshrc_blocks
  write_starship_config
  write_ghostty_config
  install_copilot_instructions

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
  assert_contains \
    "npm install -g --allow-scripts=@microsoft/artifacts-credprovider-wrapper --registry=${ARTIFACTS_NPM_REGISTRY} ${MICROSOFT_NPM_GLOBAL_PACKAGES[*]}" \
    "$npm_log"
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
  assert_contains "nix build --no-link ${FLAKE_URL}#default" "$command_log"
  assert_contains \
    "profile ${FLAKE_URL}#default packages.x86_64-linux.default" \
    "$command_log"

  : >"$command_log"
  IS_WSL=0
  assert_equals "workstation" "$(nix_tool_output "$IS_WSL")"
  install_dev_tools
  assert_contains "nix build --no-link ${FLAKE_URL}#workstation" "$command_log"
  assert_contains \
    "profile ${FLAKE_URL}#workstation packages.x86_64-linux.workstation" \
    "$command_log"
}

test_platform_output_autodetection() (
  local system_name="Linux"
  local mock_wsl_state=1

  # shellcheck disable=SC2329
  uname() {
    [[ "${1:-}" == "-s" ]] \
      || fail_test "Unexpected uname command: $*"
    printf '%s\n' "$system_name"
  }

  # shellcheck disable=SC2329
  is_wsl() {
    [[ "$mock_wsl_state" -eq 1 ]]
  }

  assert_equals "default" "$(nix_tool_output)"

  mock_wsl_state=0
  assert_equals "workstation" "$(nix_tool_output)"

  system_name="Darwin"
  mock_wsl_state=1
  assert_equals "workstation" "$(nix_tool_output)"
)

test_legacy_tool_cleanup() {
  local legacy_csharpier="${HOME}/.local/bin/csharpier"
  local legacy_dotnet="${HOME}/.dotnet"
  local legacy_installer="${HOME}/.cache/${SCRIPT_MARKER}/dotnet-install.sh"

  mkdir -p \
    "${legacy_dotnet}/sdk" \
    "${legacy_dotnet}/tools" \
    "${HOME}/.local/bin" \
    "$(dirname "$legacy_installer")"
  touch "${legacy_dotnet}/sdk/user-managed-sdk"
  touch "${legacy_dotnet}/tools/csharpier"
  touch "$legacy_installer"
  ln -s "${legacy_dotnet}/tools/csharpier" "$legacy_csharpier"

  remove_legacy_tool_installations

  [[ -f "${legacy_dotnet}/sdk/user-managed-sdk" ]] \
    || fail_test "Non-empty .NET installation was removed without opt-in"
  [[ ! -e "$legacy_csharpier" && ! -L "$legacy_csharpier" ]] \
    || fail_test "Legacy CSharpier shim was not removed"
  [[ ! -e "$legacy_installer" ]] \
    || fail_test "Legacy cached installer was not removed"

  ln -s "${HOME}/custom-tools/csharpier" "$legacy_csharpier"
  remove_legacy_tool_installations
  [[ -d "$legacy_dotnet" ]] \
    || fail_test "Non-empty .NET installation was removed without opt-in"
  [[ -L "$legacy_csharpier" ]] \
    || fail_test "Non-legacy CSharpier shim was removed"

  BOOTSTRAP_REMOVE_LEGACY_DOTNET=1 remove_legacy_tool_installations
  [[ ! -e "$legacy_dotnet" ]] \
    || fail_test "Opted-in legacy .NET installation was not removed"
  [[ -L "$legacy_csharpier" ]] \
    || fail_test "Non-legacy CSharpier shim was removed during opted-in cleanup"
}

test_managed_config_is_idempotent
test_npm_registry_override
test_platform_output_selection
test_platform_output_autodetection
test_legacy_tool_cleanup

printf 'Bootstrap integration checks passed\n'
