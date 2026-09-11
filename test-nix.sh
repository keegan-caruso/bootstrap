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
  nix fmt -- --check flake.nix home.nix
)

printf 'Evaluating all supported Nix systems\n'
nix flake check --all-systems --no-build "path:${FLAKE_DIR}"

printf 'Building the current system tool environment\n'
tool_environment="$(
  nix build --no-link --print-out-paths \
    "path:${FLAKE_DIR}#$(nix_tool_output)"
)"
[[ ! -e "${tool_environment}/bin/git-credential-manager-wsl" ]] || {
  printf 'WSL credential helper must be owned only by Home Manager\n' >&2
  exit 1
}

current_system="$(nix eval --impure --raw --expr builtins.currentSystem)"
home_variant=""
if is_wsl; then
  home_variant="-wsl"
fi
printf 'Building the current Home Manager configuration\n'
home_manager_generation="$(
  nix build --no-link --print-out-paths \
    "path:${FLAKE_DIR}#homeConfigurations.\"keegancaruso@${current_system}${home_variant}\".activationPackage"
)"
home_files="$(readlink "${home_manager_generation}/home-files")"
if is_wsl; then
  [[ -e "${home_files}/.local/bin/git-credential-manager-wsl" ]] || {
    printf 'WSL Home Manager configuration is missing its credential helper\n' >&2
    exit 1
  }
fi

printf 'Testing .NET runtime discovery in development and generated home shells\n'
env -u DOTNET_ROOT nix develop "path:${FLAKE_DIR}" --command bash -euc '
  test -x "$DOTNET_ROOT/dotnet"
  test -d "$DOTNET_ROOT/host/fxr"
  test -d "$DOTNET_ROOT/shared/Microsoft.NETCore.App/8.0."*
  expected_root="$DOTNET_ROOT"
  zsh_root="$(env -u DOTNET_ROOT zsh -f -c \
    '\''source "$1"; printenv DOTNET_ROOT'\'' runtime-discovery "$1/.zshenv")"
  bash_root="$(env -u DOTNET_ROOT bash --noprofile --norc -c \
    '\''source "$1"; printenv DOTNET_ROOT'\'' \
    runtime-discovery "$1/.config/codex-dev-shell/bashrc")"
  test "$zsh_root" = "$expected_root"
  test "$bash_root" = "$expected_root"
' runtime-discovery "$home_files"

printf 'Testing development tools without an inherited interactive PATH\n'
env -u FNM_MULTISHELL_PATH -u FNM_DIR \
  PATH="$(dirname "$(command -v nix)"):/usr/bin:/bin" \
  nix develop "path:${FLAKE_DIR}" --command bash -euc '
    test "$(command -v node)" = "$FNM_DIR/aliases/default/bin/node"
    node --version
    npm --version
    pnpm --version
    tsc --version
    test -x "$(command -v typescript-language-server)"
    csharp-ls --version
  '

printf 'Testing the generated C# language-server configuration\n'
lsp_command="$(jq -er '.lspServers.csharp.command' "${home_files}/.copilot/lsp-config.json")"
"$lsp_command" --version

if [[ "$(uname -s)" == "Linux" ]]; then
  printf 'Testing Linux sandbox runtime dependencies\n'
  nix develop "path:${FLAKE_DIR}" --command bash -euc '
    bwrap --version
    slirp4netns --version
    iptables --version
    ip6tables --version
  '

  printf 'Testing declared runtime paths with the rest of HOME hidden\n'
  (
    runtime_test_root="$(mktemp -d)"
    trap 'rm -rf -- "$runtime_test_root"' EXIT
    runtime_settings="${runtime_test_root}/settings.json"
    COPILOT_SETTINGS_FILE="$runtime_settings" \
      "${SCRIPT_DIR}/configure-copilot-sandbox.sh" --configure-only >/dev/null
    sandbox_args=(--ro-bind / / --tmpfs "$HOME" --tmpfs /tmp --dev /dev --proc /proc --chdir /tmp)
    while IFS= read -r path; do
      if [[ -e "$path" ]]; then
        sandbox_args+=(--ro-bind "$path" "$path")
      fi
    done < <(jq -r '.sandbox.userPolicy.filesystem.readonlyPaths[]' "$runtime_settings")
    while IFS= read -r path; do
      if [[ -e "$path" ]]; then
        sandbox_args+=(--bind "$path" "$path")
      fi
    done < <(jq -r '.sandbox.userPolicy.filesystem.readwritePaths[]' "$runtime_settings")
    while IFS= read -r path; do
      if [[ -d "$path" ]]; then
        sandbox_args+=(--tmpfs "$path")
      fi
    done < <(jq -r '.sandbox.userPolicy.filesystem.deniedPaths[]' "$runtime_settings")
    profile_path="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/bootstrap"
    fnm_path="${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
    bwrap "${sandbox_args[@]}" --clearenv \
      --setenv HOME "$HOME" \
      --setenv PATH "$profile_path/bin:$HOME/.local/bin:$fnm_path/aliases/default/bin:/usr/bin:/bin" \
      /bin/bash -euc '
        test "$(command -v jq)" = "$1/bin/jq"
        jq --version
        dotnet --list-sdks
        csharp-ls --version
        node --version
      ' runtime-visibility "$profile_path"
  )

  printf 'Testing the Playwright browser environment\n'
  nix develop "path:${FLAKE_DIR}" --command playwright-run bash -c '
    test "$PLAYWRIGHT_BROWSERS_PATH" = "$HOME/.cache/ms-playwright"
    ldconfig -p | grep -q "libgbm.so.1"
    ldconfig -p | grep -q "libnss3.so"
  '
fi

printf 'Nix bootstrap checks passed\n'
