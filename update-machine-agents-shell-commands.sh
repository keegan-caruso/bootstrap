#!/usr/bin/env bash
set -euo pipefail

SCRIPT_MARKER="codex-dev-shell"
DEFAULT_AGENTS_MD="${HOME}/.copilot/agents.md"

log() {
  printf '[update-machine-agents] %s\n' "$*"
}

fail() {
  printf '[update-machine-agents] %s\n' "$*" >&2
  exit 1
}

ensure_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file"
}

upsert_section() {
  local file="$1"
  local section="$2"
  local content="$3"
  local start="<!-- >>> ${SCRIPT_MARKER}:${section} -->"
  local end="<!-- <<< ${SCRIPT_MARKER}:${section} -->"
  local tmp

  ensure_file "$file"
  tmp="$(mktemp)" || fail "Failed to create temporary file"

  (
    flock -x 9 || fail "Failed to acquire lock on ${file}"
    awk -v start="$start" -v end="$end" -v block="$content" '
      BEGIN {
        in_block = 0
        replaced = 0
      }
      $0 == start {
        print start
        print block
        print end
        in_block = 1
        replaced = 1
        next
      }
      $0 == end {
        in_block = 0
        next
      }
      !in_block {
        print
      }
      END {
        if (!replaced) {
          if (NR > 0) {
            print ""
          }
          print start
          print block
          print end
        }
      }
    ' "$file" >"$tmp"

    mv "$tmp" "$file"
  ) 9>"${file}.lock"
}

main() {
  local agents_md="${1:-${MACHINE_AGENTS_MD:-${DEFAULT_AGENTS_MD}}}"
  local section_content

  section_content="$(cat <<'EOF'
## Shell command tools

Use the current shell tools for terminal execution:

- `bash`: start a shell command.
- `read_bash`: read output from a running shell session.
- `write_bash`: send input to a running shell session.
- `stop_bash`: stop a running shell session.
EOF
)"

  upsert_section "$agents_md" "shell-commands" "$section_content"
  log "Updated shell command section in ${agents_md}"
}

main "$@"
