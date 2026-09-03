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
  write_zshrc_blocks

  assert_contains "keep-before" "${HOME}/.zprofile"
  assert_contains "keep-after" "${HOME}/.zprofile"
  assert_not_contains "${SCRIPT_MARKER}:homebrew" "${HOME}/.zprofile"
  assert_marker_once "# >>> ${SCRIPT_MARKER}:home-manager" "${HOME}/.zshrc"
  # shellcheck disable=SC2016
  assert_contains 'source "$HOME/.config/codex-dev-shell/zshrc"' "${HOME}/.zshrc"

  cp -R "$HOME" "$first_run"

  remove_homebrew_shell_config
  write_zshrc_blocks

  diff -ru "$first_run" "$HOME" \
    || fail_test "Managed configuration changed on the second run"

  IS_WSL=1
  write_bashrc_blocks
  write_bashrc_blocks
  assert_marker_once "# >>> ${SCRIPT_MARKER}:aliases" "${HOME}/.bashrc"
  # shellcheck disable=SC2016
  assert_contains 'source "$HOME/.config/codex-dev-shell/bashrc"' "${HOME}/.bashrc"
}

test_home_manager_migration_safety() {
  local managed_file="${HOME}/.config/starship.toml"
  local fontconfig_file="${HOME}/.config/fontconfig/fonts.conf"
  local symlink_target="${TEST_ROOT}/user-starship.toml"

  mkdir -p "$(dirname "$managed_file")"
  cat >"$managed_file" <<EOF
# >>> ${SCRIPT_MARKER}:config
managed
# <<< ${SCRIPT_MARKER}:config
EOF
  prepare_home_manager_file "$managed_file" "config"
  [[ ! -e "$managed_file" ]] \
    || fail_test "Legacy fully managed file was not prepared for Home Manager"

  cat >"$managed_file" <<EOF
keep
# >>> ${SCRIPT_MARKER}:config
managed
# <<< ${SCRIPT_MARKER}:config
EOF
  if (prepare_home_manager_file "$managed_file" "config") >/dev/null 2>&1; then
    fail_test "Home Manager migration accepted unmanaged user content"
  fi
  assert_contains "keep" "$managed_file"
  rm -f "$managed_file"

  cat >"$managed_file" <<EOF
# >>> ${SCRIPT_MARKER}:config
managed
user content after missing end marker
EOF
  if (prepare_home_manager_file "$managed_file" "config") >/dev/null 2>&1; then
    fail_test "Home Manager migration accepted a malformed legacy block"
  fi
  assert_contains "user content after missing end marker" "$managed_file"
  rm -f "$managed_file"

  printf 'user managed\n' >"$symlink_target"
  ln -s "$symlink_target" "$managed_file"
  if (prepare_home_manager_file "$managed_file" "config") >/dev/null 2>&1; then
    fail_test "Home Manager migration accepted a user-managed symlink"
  fi
  [[ -L "$managed_file" ]] \
    || fail_test "Home Manager migration replaced a user-managed symlink"
  assert_contains "user managed" "$symlink_target"
  rm -f "$managed_file"

  ln -s "/nix/store/example-package/starship.toml" "$managed_file"
  if (prepare_home_manager_file "$managed_file" "config") >/dev/null 2>&1; then
    fail_test "Home Manager migration accepted an arbitrary Nix store symlink"
  fi
  [[ -L "$managed_file" ]] \
    || fail_test "Home Manager migration replaced an arbitrary Nix store symlink"
  rm -f "$managed_file"

  ln -s \
    "/nix/store/example-home-manager-files/.config/starship.toml" \
    "$managed_file"
  prepare_home_manager_file "$managed_file" "config"
  [[ -L "$managed_file" ]] \
    || fail_test "Home Manager migration rejected its own managed symlink"
  rm -f "$managed_file"

  mkdir -p "$(dirname "$fontconfig_file")"
  cat >"$fontconfig_file" <<EOF
<fontconfig>
<!-- >>> ${SCRIPT_MARKER}:nix-profile-fonts -->
<dir>/old/profile/share/fonts</dir>
<!-- <<< ${SCRIPT_MARKER}:nix-profile-fonts -->
<match>keep</match>
</fontconfig>
EOF
  chmod 640 "$fontconfig_file"
  prepare_home_manager_migration
  assert_not_contains "nix-profile-fonts" "$fontconfig_file"
  assert_contains "<match>keep</match>" "$fontconfig_file"
  [[ "$(stat -c '%a' "$fontconfig_file")" == "640" ]] \
    || fail_test "Fontconfig migration did not preserve file permissions"
  finish_home_manager_migration
}

test_home_manager_activation_rollback() {
  local managed_file="${HOME}/.config/starship.toml"
  local failed_activation_package="${TEST_ROOT}/failed-home-manager-generation"
  local previous_generation="${TEST_ROOT}/previous-home-manager-generation"
  local rollback_log="${TEST_ROOT}/home-manager-rollback.log"
  local generation_root="${XDG_STATE_HOME}/home-manager/gcroots/current-home"

  mkdir -p \
    "$(dirname "$managed_file")" \
    "$failed_activation_package" \
    "$previous_generation" \
    "$(dirname "$generation_root")"
  cat >"$managed_file" <<EOF
# >>> ${SCRIPT_MARKER}:config
managed
# <<< ${SCRIPT_MARKER}:config
EOF
  printf '#!/usr/bin/env bash\nexit 1\n' >"${failed_activation_package}/activate"
  chmod +x "${failed_activation_package}/activate"
  printf '#!/usr/bin/env bash\nprintf "rolled back\\n" >%q\n' "$rollback_log" \
    >"${previous_generation}/activate"
  chmod +x "${previous_generation}/activate"
  ln -s "$previous_generation" "$generation_root"

  nix() {
    if [[ "${1:-}" == "eval" ]]; then
      printf 'x86_64-linux'
      return
    fi
    printf '%s\n' "$failed_activation_package"
  }

  IS_WSL=1
  if (activate_home_manager) >/dev/null 2>&1; then
    fail_test "Home Manager activation failure was reported as success"
  fi
  assert_contains "${SCRIPT_MARKER}:config" "$managed_file"
  assert_contains "rolled back" "$rollback_log"
  rm -f "$generation_root"
}

test_home_manager_activation_signal_rollback() {
  local managed_file="${HOME}/.config/starship.toml"
  local interrupted_activation_package="${TEST_ROOT}/interrupted-home-manager-generation"

  mkdir -p "$(dirname "$managed_file")" "$interrupted_activation_package"
  cat >"$managed_file" <<EOF
# >>> ${SCRIPT_MARKER}:config
managed
# <<< ${SCRIPT_MARKER}:config
EOF
  printf '#!/usr/bin/env bash\nkill -TERM "$PPID"\nexit 0\n' \
    >"${interrupted_activation_package}/activate"
  chmod +x "${interrupted_activation_package}/activate"

  nix() {
    if [[ "${1:-}" == "eval" ]]; then
      printf 'x86_64-linux'
      return
    fi
    printf '%s\n' "$interrupted_activation_package"
  }

  IS_WSL=1
  if (activate_home_manager) >/dev/null 2>&1; then
    fail_test "Interrupted Home Manager activation was reported as success"
  fi
  assert_contains "${SCRIPT_MARKER}:config" "$managed_file"
}

test_malformed_shell_block_safety() {
  local shell_file="${HOME}/.zshrc"

  cat >"$shell_file" <<EOF
# >>> ${SCRIPT_MARKER}:path
managed
user content after missing end marker
EOF
  if (remove_block "$shell_file" "path") >/dev/null 2>&1; then
    fail_test "Shell migration accepted a malformed managed block"
  fi
  assert_contains "user content after missing end marker" "$shell_file"
}

test_wsl_browser_link_preserves_custom_opener() {
  local custom_opener="${HOME}/.local/bin/xdg-open"

  mkdir -p "$(dirname "$custom_opener")"
  printf 'custom\n' >"$custom_opener"

  IS_WSL=1
  install_wsl_browser_link
  assert_contains "custom" "$custom_opener"
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

test_home_manager_selection() {
  local test_activation_package="${TEST_ROOT}/home-manager-generation"
  local command_log="${TEST_ROOT}/home-manager.log"

  mkdir -p "$test_activation_package"
  printf '#!/usr/bin/env bash\nprintf "activated\\\\n" >>%q\n' "$command_log" \
    >"${test_activation_package}/activate"
  chmod +x "${test_activation_package}/activate"

  nix() {
    if [[ "${1:-}" == "eval" ]]; then
      printf 'x86_64-linux'
      return
    fi

    printf 'nix %s\n' "$*" >>"$command_log"
    printf '%s\n' "$test_activation_package"
  }

  IS_WSL=1
  activate_home_manager
  assert_contains \
    "homeConfigurations.\"keegancaruso@x86_64-linux-wsl\".activationPackage" \
    "$command_log"
  assert_contains "activated" "$command_log"
}

test_git_managed_include() {
  local managed_config="${HOME}/.config/git/bootstrap.config"

  mkdir -p "$(dirname "$managed_config")"
  printf '[core]\n  pager = delta\n' >"$managed_config"

  GIT_EMAIL="keegan@example.test"
  IS_WSL=0
  configure_git

  assert_equals "Keegan Caruso" "$(git config --global user.name)"
  assert_equals "$GIT_EMAIL" "$(git config --global user.email)"
  assert_equals "$managed_config" "$(git config --global --get include.path)"
  assert_equals "delta" "$(git config --global --includes core.pager)"
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
test_home_manager_migration_safety
test_wsl_browser_link_preserves_custom_opener
test_npm_registry_override
test_platform_output_selection
test_home_manager_selection
test_home_manager_activation_rollback
test_home_manager_activation_signal_rollback
test_malformed_shell_block_safety
test_platform_output_autodetection
test_git_managed_include
test_legacy_tool_cleanup

printf 'Bootstrap integration checks passed\n'
