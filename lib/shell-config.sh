#!/usr/bin/env bash

ensure_file() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file"
}

upsert_block() {
  local file="$1"
  local name="$2"
  local content="$3"
  local start="# >>> ${SCRIPT_MARKER}:${name}"
  local end="# <<< ${SCRIPT_MARKER}:${name}"
  local lock_dir="${file}.lock.d"
  local tmp

  ensure_file "$file"
  legacy_markers_are_well_formed "$file" "$start" "$end" \
    || fail "Cannot update ${file}: its ${name} managed block is malformed."
  tmp="$(mktemp)" || fail "Failed to create temporary file"

  (
    local attempt
    local acquired=0
    for (( attempt = 0; attempt < 100; attempt++ )); do
      if mkdir "$lock_dir" 2>/dev/null; then
        acquired=1
        break
      fi
      sleep 0.05
    done
    (( acquired )) || fail "Failed to acquire lock on ${file}"
    trap 'rmdir "$lock_dir"' EXIT

    # Environment values avoid awk interpreting backslash escapes from templates.
    BLOCK_CONTENT="$content" awk -v start="$start" -v end="$end" '
      BEGIN {
        in_block = 0
        replaced = 0
      }
      $0 == start {
        print start
        print ENVIRON["BLOCK_CONTENT"]
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
          print ENVIRON["BLOCK_CONTENT"]
          print end
        }
      }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
  )
}

remove_block() {
  local file="$1"
  local name="$2"
  local start="# >>> ${SCRIPT_MARKER}:${name}"
  local end="# <<< ${SCRIPT_MARKER}:${name}"
  local lock_dir="${file}.lock.d"
  local tmp

  [[ -f "$file" ]] || return
  legacy_markers_are_well_formed "$file" "$start" "$end" \
    || fail "Cannot update ${file}: its ${name} managed block is malformed."
  tmp="$(mktemp)" || fail "Failed to create temporary file"

  (
    local attempt
    local acquired=0
    for (( attempt = 0; attempt < 100; attempt++ )); do
      if mkdir "$lock_dir" 2>/dev/null; then
        acquired=1
        break
      fi
      sleep 0.05
    done
    (( acquired )) || fail "Failed to acquire lock on ${file}"
    trap 'rmdir "$lock_dir"' EXIT

    awk -v start="$start" -v end="$end" '
      $0 == start { in_block = 1; next }
      $0 == end { in_block = 0; next }
      !in_block { print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
  )
}

write_zshrc_blocks() {
  local zshrc="${HOME}/.zshrc"

  ensure_file "$zshrc"
  remove_block "$zshrc" "path"
  remove_block "$zshrc" "interactive"
  remove_block "$zshrc" "prompt"
  remove_block "$zshrc" "shell-tools"
  remove_block "$zshrc" "syntax-highlighting"
  # shellcheck disable=SC2016
  upsert_block "$zshrc" "home-manager" \
    'source "$HOME/.config/codex-dev-shell/zshrc"'
}

write_bashrc_blocks() {
  [[ "$IS_WSL" -eq 1 ]] || return

  ensure_file "${HOME}/.bashrc"
  remove_block "${HOME}/.bashrc" "aliases"

  # shellcheck disable=SC2016
  upsert_block "${HOME}/.bashrc" "aliases" \
    'source "$HOME/.config/codex-dev-shell/bashrc"'
}

reconcile_shell_loaders() {
  write_zshrc_blocks
  if [[ "$IS_WSL" -eq 1 ]]; then
    remove_block "${HOME}/.bashrc" "wsl-zsh-handoff"
    write_bashrc_blocks
  fi
}
