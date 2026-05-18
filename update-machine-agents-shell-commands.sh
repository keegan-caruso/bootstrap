#!/usr/bin/env bash
set -euo pipefail

SCRIPT_MARKER="codex-dev-shell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_AGENTS_MD="${HOME}/.copilot/agents.md"
DEFAULT_SECTION="shell-commands"
DEFAULT_TEMPLATE_PATH="${SCRIPT_DIR}/templates/machine-agents/shell-command-tools.md"

log() {
  printf '[update-machine-agents] %s\n' "$*"
}

fail() {
  printf '[update-machine-agents] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [legacy-target-path]

Adds or updates a managed section in one or more machine-scoped agents files.

Options:
  --file PATH       Target agents file path (repeatable)
  --section NAME    Managed section marker name (default: ${DEFAULT_SECTION})
  --dry-run         Print diffs for pending updates; do not write files
  --check           Exit non-zero if any target would change
  --help            Show this help text

Environment:
  MACHINE_AGENTS_MD Legacy single-target override when --file is not provided
EOF
}

ensure_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file"
}

normalize_line_endings_and_trim() {
  local input="$1"
  awk '
    {
      sub(/\r$/, "")
      lines[++n] = $0
    }
    END {
      while (n > 0 && lines[n] == "") {
        n--
      }
      for (i = 1; i <= n; i++) {
        print lines[i]
      }
    }
  ' <<<"$input"
}

read_template() {
  local template_path="$1"

  if [[ ! -f "$template_path" ]]; then
    fail "Template not found: $template_path"
  fi

  normalize_line_endings_and_trim "$(cat "$template_path")"
}

render_upserted_content() {
  local source_file="$1"
  local section="$2"
  local content="$3"
  local output_path="$4"
  local start="<!-- >>> ${SCRIPT_MARKER}:${section} -->"
  local end="<!-- <<< ${SCRIPT_MARKER}:${section} -->"

  awk -v start="$start" -v end="$end" -v block="$content" '
    BEGIN {
      in_block = 0
      replaced = 0
    }
    {
      sub(/\r$/, "")
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
      lines[++n] = $0
    }
    END {
      for (i = 1; i <= n; i++) {
        print lines[i]
      }
      if (!replaced) {
        if (n > 0) {
          print ""
        }
        print start
        print block
        print end
      }
    }
  ' "$source_file" >"$output_path"
}

target_would_change() {
  local file="$1"
  local section="$2"
  local content="$3"
  local source_file="$file"
  local tmp

  if [[ ! -f "$file" ]]; then
    source_file="/dev/null"
  fi

  tmp="$(mktemp)" || fail "Failed to create temporary file"
  render_upserted_content "$source_file" "$section" "$content" "$tmp"

  if [[ ! -f "$file" ]] || ! cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi

  rm -f "$tmp"
  return 1
}

print_target_diff() {
  local file="$1"
  local section="$2"
  local content="$3"
  local source_file="$file"
  local tmp

  if [[ ! -f "$file" ]]; then
    source_file="/dev/null"
  fi

  tmp="$(mktemp)" || fail "Failed to create temporary file"
  render_upserted_content "$source_file" "$section" "$content" "$tmp"
  diff -u \
    --label "${file} (current)" "$source_file" \
    --label "${file} (updated)" "$tmp" || true
  rm -f "$tmp"
}

apply_upsert_section() {
  local file="$1"
  local section="$2"
  local content="$3"
  local tmp

  ensure_file "$file"
  tmp="$(mktemp)" || fail "Failed to create temporary file"

  exec 9>"${file}.lock" || fail "Failed to open lock file for ${file}"
  flock -x 9 || fail "Failed to acquire lock on ${file}"
  render_upserted_content "$file" "$section" "$content" "$tmp"

  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    exec 9>&-
    return 1
  fi

  mv "$tmp" "$file"
  exec 9>&-
  return 0
}

main() {
  local section="${DEFAULT_SECTION}"
  local template_path="${DEFAULT_TEMPLATE_PATH}"
  local dry_run=0
  local check_only=0
  local env_target="${MACHINE_AGENTS_MD:-}"
  local legacy_target=""
  local -a target_files=()
  local section_content
  local changed_count=0
  local file

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        [[ $# -ge 2 ]] || fail "--file requires a path"
        target_files+=("$2")
        shift 2
        ;;
      --section)
        [[ $# -ge 2 ]] || fail "--section requires a name"
        section="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --check)
        check_only=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --*)
        fail "Unknown option: $1"
        ;;
      *)
        if [[ -n "$legacy_target" ]]; then
          fail "Unexpected positional argument: $1"
        fi
        legacy_target="$1"
        shift
        ;;
    esac
  done

  if [[ "${#target_files[@]}" -eq 0 ]]; then
    target_files+=("${legacy_target:-${env_target:-${DEFAULT_AGENTS_MD}}}")
  fi

  section_content="$(read_template "$template_path")"

  for file in "${target_files[@]}"; do
    if target_would_change "$file" "$section" "$section_content"; then
      changed_count=$((changed_count + 1))

      if [[ "$dry_run" -eq 1 ]]; then
        print_target_diff "$file" "$section" "$section_content"
      fi

      if [[ "$check_only" -eq 0 && "$dry_run" -eq 0 ]]; then
        apply_upsert_section "$file" "$section" "$section_content" || true
        log "Updated section '${section}' in ${file}"
      fi
    else
      log "No changes needed for ${file}"
    fi
  done

  if [[ "$check_only" -eq 1 ]]; then
    if [[ "$changed_count" -gt 0 ]]; then
      fail "${changed_count} file(s) require updates"
    fi
    log "All target files are up to date"
    return
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    if [[ "$changed_count" -gt 0 ]]; then
      log "Dry-run found ${changed_count} file(s) with pending updates"
    else
      log "Dry-run found no pending updates"
    fi
  fi
}

main "$@"
