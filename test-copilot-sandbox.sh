#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_ROOT="$(mktemp -d)"
SETTINGS_FILE="${TEST_ROOT}/settings.json"
export NIX_PROFILES_PATH="${TEST_ROOT}/nix-profiles"
export FNM_DIR="${TEST_ROOT}/fnm"
export COPILOT_LOCAL_BIN_PATH="${TEST_ROOT}/local-bin"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail_test() {
  printf 'Test failed: %s\n' "$*" >&2
  exit 1
}

cat >"$SETTINGS_FILE" <<'EOF'
{
  "theme": "github",
  "sandbox": {
    "customSetting": "preserved",
    "userPolicy": {
      "filesystem": {
        "deniedPaths": [
          "/already-denied"
        ],
        "readonlyPaths": [
          "/already-readonly"
        ],
        "readwritePaths": [
          "/already-readwrite"
        ]
      }
    }
  }
}
EOF

COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
COPILOT_PACKAGE_CACHE_PATH="${TEST_ROOT}/copilot-pkg" \
PLAYWRIGHT_BROWSER_CACHE_PATH="${TEST_ROOT}/ms-playwright" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" >/dev/null

jq -e '
  .theme == "github"
  and .sandbox.customSetting == "preserved"
  and .sandbox.enabled == true
  and .sandbox.allowBypass == false
  and .sandbox.addCurrentWorkingDirectory == true
  and .sandbox.allowDevToolAccess == true
  and .sandbox.auth == {"git": true, "gh": true}
  and .sandbox.sandboxLspServers == true
  and .sandbox.userPolicy.filesystem.deniedPaths == ["/already-denied", "/mnt/c"]
  and .sandbox.userPolicy.filesystem.readonlyPaths
    == (["/already-readonly", "/nix/store", $package_cache,
         env.NIX_PROFILES_PATH, env.FNM_DIR, env.COPILOT_LOCAL_BIN_PATH] | sort)
  and .sandbox.userPolicy.filesystem.readwritePaths
    == ["/already-readwrite", $browser_cache]
  and .sandbox.userPolicy.filesystem.clearPolicyOnExit == false
  and .sandbox.userPolicy.network.allowOutbound == true
  and .sandbox.userPolicy.network.allowLocalNetwork == true
' \
  --arg package_cache "${TEST_ROOT}/copilot-pkg" \
  --arg browser_cache "${TEST_ROOT}/ms-playwright" \
  "$SETTINGS_FILE" >/dev/null \
  || fail_test "Sandbox settings were not merged correctly."

[[ "$(stat -c '%a' "$SETTINGS_FILE")" == "600" ]] \
  || fail_test "Copilot settings permissions are not private."

cp "$SETTINGS_FILE" "${TEST_ROOT}/first-run.json"
COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
COPILOT_PACKAGE_CACHE_PATH="${TEST_ROOT}/copilot-pkg" \
PLAYWRIGHT_BROWSER_CACHE_PATH="${TEST_ROOT}/ms-playwright" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" >/dev/null
cmp -s "${TEST_ROOT}/first-run.json" "$SETTINGS_FILE" \
  || fail_test "Sandbox configuration is not idempotent."

COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
COPILOT_PACKAGE_CACHE_PATH="${TEST_ROOT}/copilot-pkg" \
PLAYWRIGHT_BROWSER_CACHE_PATH="${TEST_ROOT}/ms-playwright" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" --configure-only >/dev/null
cmp -s "${TEST_ROOT}/first-run.json" "$SETTINGS_FILE" \
  || fail_test "Configure-only changed an enabled sandbox."

printf '{"sandbox":{"enabled":false}}\n' >"$SETTINGS_FILE"
COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" --configure-only >/dev/null
jq -e '
  .sandbox.enabled == false
  and .sandbox.allowBypass == false
  and (.sandbox.userPolicy.filesystem.readonlyPaths | index(env.NIX_PROFILES_PATH) != null)
  and (.sandbox.userPolicy.filesystem.readonlyPaths | index(env.FNM_DIR) != null)
' "$SETTINGS_FILE" >/dev/null \
  || fail_test "Configure-only did not preserve disabled state while updating paths."

cp "$SETTINGS_FILE" "${TEST_ROOT}/before-invalid-arguments"
if COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" --unknown >/dev/null 2>&1; then
  fail_test "Unknown arguments were accepted."
fi
cmp -s "${TEST_ROOT}/before-invalid-arguments" "$SETTINGS_FILE" \
  || fail_test "Invalid arguments changed settings."

printf '{ invalid json\n' >"$SETTINGS_FILE"
cp "$SETTINGS_FILE" "${TEST_ROOT}/invalid-original"
if COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
  COPILOT_PACKAGE_CACHE_PATH="${TEST_ROOT}/copilot-pkg" \
  PLAYWRIGHT_BROWSER_CACHE_PATH="${TEST_ROOT}/ms-playwright" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" >/dev/null 2>&1; then
  fail_test "Invalid existing settings were accepted."
fi
cmp -s "${TEST_ROOT}/invalid-original" "$SETTINGS_FILE" \
  || fail_test "Invalid existing settings were modified."

if [[ "$(uname -s)" == "Linux" ]]; then
  for missing_command in bwrap slirp4netns iptables; do
    test_bin="${TEST_ROOT}/without-${missing_command}"
    mkdir -p "$test_bin"
    for dependency in bash jq uname; do
      ln -s "$(command -v "$dependency")" "$test_bin/$dependency"
    done
    for dependency in bwrap slirp4netns iptables; do
      if [[ "$dependency" != "$missing_command" ]]; then
        ln -s "$(type -P true)" "$test_bin/$dependency"
      fi
    done
    printf '{"sandbox":{"enabled":false}}\n' >"$SETTINGS_FILE"
    cp "$SETTINGS_FILE" "${TEST_ROOT}/disabled-original"
    if PATH="$test_bin" COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
      "${REPO_DIR}/configure-copilot-sandbox.sh" >"${TEST_ROOT}/missing.log" 2>&1; then
      fail_test "Sandbox was enabled without ${missing_command}."
    fi
    grep -Fq "${missing_command} is required" "${TEST_ROOT}/missing.log" \
      || fail_test "Missing ${missing_command} was not diagnosed."
    cmp -s "${TEST_ROOT}/disabled-original" "$SETTINGS_FILE" \
      || fail_test "Settings were changed despite missing ${missing_command}."
    [[ ! -e "${SETTINGS_FILE}.lock.d" ]] \
      || fail_test "Missing dependency left a settings lock."
  done
fi

printf 'Copilot sandbox configuration checks passed\n'
