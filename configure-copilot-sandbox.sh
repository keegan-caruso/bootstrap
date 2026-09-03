#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${COPILOT_SETTINGS_FILE:-${HOME}/.copilot/settings.json}"
DENIED_PATH="/mnt/c"
LOCK_DIR="${SETTINGS_FILE}.lock.d"
TMP_FILE=""
LOCK_ACQUIRED=0

log() {
  printf '[copilot-sandbox] %s\n' "$*"
}

fail() {
  printf '[copilot-sandbox] %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
  (( LOCK_ACQUIRED == 0 )) || rmdir "$LOCK_DIR" 2>/dev/null || true
}

command -v jq >/dev/null 2>&1 \
  || fail "jq is required. Run bootstrap-nix.sh first."

mkdir -p "$(dirname "$SETTINGS_FILE")"

for _ in {1..100}; do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_ACQUIRED=1
    break
  fi
  sleep 0.05
done
(( LOCK_ACQUIRED == 1 )) \
  || fail "Failed to acquire lock on ${SETTINGS_FILE}"
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

TMP_FILE="$(mktemp "${SETTINGS_FILE}.tmp.XXXXXX")" \
  || fail "Failed to create temporary settings file."

# shellcheck disable=SC2016
jq_filter='
  .sandbox.enabled = true
  | .sandbox.allowBypass = false
  | .sandbox.addCurrentWorkingDirectory = true
  | .sandbox.allowDevToolAccess = true
  | .sandbox.auth.git = true
  | .sandbox.auth.gh = true
  | .sandbox.sandboxLspServers = true
  | .sandbox.userPolicy.filesystem.deniedPaths =
      (((.sandbox.userPolicy.filesystem.deniedPaths // []) + [$denied_path]) | unique)
  | .sandbox.userPolicy.filesystem.clearPolicyOnExit = false
  | .sandbox.userPolicy.network.allowOutbound = true
  | .sandbox.userPolicy.network.allowLocalNetwork = true
'

if [[ -f "$SETTINGS_FILE" ]]; then
  jq --arg denied_path "$DENIED_PATH" "$jq_filter" "$SETTINGS_FILE" >"$TMP_FILE" \
    || fail "Existing Copilot settings are not valid JSON objects: ${SETTINGS_FILE}"
else
  jq --null-input --arg denied_path "$DENIED_PATH" "{} | ${jq_filter}" >"$TMP_FILE"
fi

chmod 0600 "$TMP_FILE"
mv -f -- "$TMP_FILE" "$SETTINGS_FILE"
TMP_FILE=""

log "Configured the global Copilot sandbox policy in ${SETTINGS_FILE}"
log "Denied path: ${DENIED_PATH}"
