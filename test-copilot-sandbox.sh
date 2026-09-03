#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_ROOT="$(mktemp -d)"
SETTINGS_FILE="${TEST_ROOT}/settings.json"

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
        ]
      }
    }
  }
}
EOF

COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
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
  and .sandbox.userPolicy.filesystem.clearPolicyOnExit == false
  and .sandbox.userPolicy.network.allowOutbound == true
  and .sandbox.userPolicy.network.allowLocalNetwork == true
' "$SETTINGS_FILE" >/dev/null \
  || fail_test "Sandbox settings were not merged correctly."

[[ "$(stat -c '%a' "$SETTINGS_FILE")" == "600" ]] \
  || fail_test "Copilot settings permissions are not private."

cp "$SETTINGS_FILE" "${TEST_ROOT}/first-run.json"
COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" >/dev/null
cmp -s "${TEST_ROOT}/first-run.json" "$SETTINGS_FILE" \
  || fail_test "Sandbox configuration is not idempotent."

printf '{ invalid json\n' >"$SETTINGS_FILE"
cp "$SETTINGS_FILE" "${TEST_ROOT}/invalid-original"
if COPILOT_SETTINGS_FILE="$SETTINGS_FILE" \
  "${REPO_DIR}/configure-copilot-sandbox.sh" >/dev/null 2>&1; then
  fail_test "Invalid existing settings were accepted."
fi
cmp -s "${TEST_ROOT}/invalid-original" "$SETTINGS_FILE" \
  || fail_test "Invalid existing settings were modified."

printf 'Copilot sandbox configuration checks passed\n'
