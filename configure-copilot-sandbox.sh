#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${COPILOT_SETTINGS_FILE:-${HOME}/.copilot/settings.json}"
DENIED_PATH="/mnt/c"
READONLY_PATH="${COPILOT_PACKAGE_CACHE_PATH:-${HOME}/.cache/copilot/pkg}"
NIX_STORE_PATH="${NIX_STORE_PATH:-/nix/store}"
NIX_PROFILES_PATH="${NIX_PROFILES_PATH:-${XDG_STATE_HOME:-${HOME}/.local/state}/nix/profiles}"
FNM_PATH="${FNM_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/fnm}"
LOCAL_BIN_PATH="${COPILOT_LOCAL_BIN_PATH:-${HOME}/.local/bin}"
READWRITE_PATH="${PLAYWRIGHT_BROWSER_CACHE_PATH:-${HOME}/.cache/ms-playwright}"
ENABLE_SANDBOX=true
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

if (( $# > 0 )); then
  [[ $# -eq 1 && "$1" == "--configure-only" ]] \
    || fail "Usage: ${0##*/} [--configure-only]"
  ENABLE_SANDBOX=false
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  for required_command in bwrap slirp4netns iptables; do
    command -v "$required_command" >/dev/null 2>&1 \
      || fail "${required_command} is required before enabling the Linux sandbox. Run bootstrap-nix.sh first."
  done
fi

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
  .sandbox.enabled = (if $enable then true else (.sandbox.enabled // false) end)
  | .sandbox.allowBypass = false
  | .sandbox.addCurrentWorkingDirectory = true
  | .sandbox.allowDevToolAccess = true
  | .sandbox.auth.git = true
  | .sandbox.auth.gh = true
  | .sandbox.sandboxLspServers = true
  | .sandbox.userPolicy.filesystem.deniedPaths =
      (((.sandbox.userPolicy.filesystem.deniedPaths // []) + [$denied_path]) | unique)
  | .sandbox.userPolicy.filesystem.readonlyPaths =
      (((.sandbox.userPolicy.filesystem.readonlyPaths // [])
        + [$readonly_path, $nix_store_path, $nix_profiles_path, $fnm_path,
           $local_bin_path]) | unique)
  | .sandbox.userPolicy.filesystem.readwritePaths =
      (((.sandbox.userPolicy.filesystem.readwritePaths // []) + [$readwrite_path]) | unique)
  | .sandbox.userPolicy.filesystem.clearPolicyOnExit = false
  | .sandbox.userPolicy.network.allowOutbound = true
  | .sandbox.userPolicy.network.allowLocalNetwork = true
'

jq_args=(
  --argjson enable "$ENABLE_SANDBOX"
  --arg denied_path "$DENIED_PATH"
  --arg readonly_path "$READONLY_PATH"
  --arg nix_store_path "$NIX_STORE_PATH"
  --arg nix_profiles_path "$NIX_PROFILES_PATH"
  --arg fnm_path "$FNM_PATH"
  --arg local_bin_path "$LOCAL_BIN_PATH"
  --arg readwrite_path "$READWRITE_PATH"
)

if [[ -f "$SETTINGS_FILE" ]]; then
  jq "${jq_args[@]}" "$jq_filter" "$SETTINGS_FILE" >"$TMP_FILE" \
    || fail "Existing Copilot settings are not valid JSON objects: ${SETTINGS_FILE}"
else
  jq --null-input "${jq_args[@]}" \
    "{} | ${jq_filter}" >"$TMP_FILE"
fi

chmod 0600 "$TMP_FILE"
mv -f -- "$TMP_FILE" "$SETTINGS_FILE"
TMP_FILE=""

log "Configured the global Copilot sandbox policy in ${SETTINGS_FILE}"
log "Denied path: ${DENIED_PATH}"
log "Read-only path: ${READONLY_PATH}"
log "Read-only path: ${NIX_STORE_PATH}"
log "Read-only path: ${NIX_PROFILES_PATH}"
log "Read-only path: ${FNM_PATH}"
log "Read-only path: ${LOCAL_BIN_PATH}"
log "Read-write path: ${READWRITE_PATH}"
if [[ "$ENABLE_SANDBOX" == false ]]; then
  log "Sandbox enablement was left unchanged."
fi
