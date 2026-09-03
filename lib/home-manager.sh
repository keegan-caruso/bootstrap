#!/usr/bin/env bash

HOME_MANAGER_MIGRATION_BACKUP=""
HOME_MANAGER_MIGRATION_PATHS=()
HOME_MANAGER_MIGRATION_COPIES=()

legacy_file_has_unmanaged_content() {
  local file="$1"
  local name="$2"
  local start="# >>> ${SCRIPT_MARKER}:${name}"
  local end="# <<< ${SCRIPT_MARKER}:${name}"

  awk -v start="$start" -v end="$end" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    !in_block && $0 !~ /^[[:space:]]*$/ { found = 1 }
    END { exit !found }
  ' "$file"
}

legacy_markers_are_well_formed() {
  local file="$1"
  local start="$2"
  local end="$3"

  awk -v start="$start" -v end="$end" '
    $0 == start {
      starts++
      if (in_block || starts > 1) {
        invalid = 1
      }
      in_block = 1
      next
    }
    $0 == end {
      ends++
      if (!in_block || ends > 1) {
        invalid = 1
      }
      in_block = 0
      next
    }
    END {
      if (invalid || in_block || starts != ends) {
        exit 1
      }
    }
  ' "$file"
}

home_manager_owned_symlink() {
  local target

  [[ -L "$1" ]] || return 1
  target="$(readlink "$1" 2>/dev/null || true)"
  [[ "$target" == /nix/store/*-home-manager-files/* ]]
}

validate_home_manager_file() {
  local file="$1"
  local legacy_block="$2"

  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ -L "$file" ]]; then
    home_manager_owned_symlink "$file" \
      || fail "Cannot migrate ${file}: it is a user-managed symlink."
    return
  fi

  if ! legacy_markers_are_well_formed \
    "$file" \
    "# >>> ${SCRIPT_MARKER}:${legacy_block}" \
    "# <<< ${SCRIPT_MARKER}:${legacy_block}"
  then
    fail "Cannot migrate ${file}: its legacy managed block is malformed."
  fi
  if legacy_file_has_unmanaged_content "$file" "$legacy_block"; then
    fail "Cannot migrate ${file}: it contains content outside the legacy managed block."
  fi
  return 0
}

validate_legacy_fontconfig() {
  local file="${HOME}/.config/fontconfig/fonts.conf"
  local marker="<!-- >>> ${SCRIPT_MARKER}:nix-profile-fonts -->"

  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ -L "$file" ]] && grep -Fq "$marker" "$file"; then
    fail "Cannot migrate ${file}: it is a user-managed symlink containing legacy configuration."
  fi
  if [[ ! -L "$file" ]] && ! legacy_markers_are_well_formed \
    "$file" \
    "$marker" \
    "<!-- <<< ${SCRIPT_MARKER}:nix-profile-fonts -->"
  then
    fail "Cannot migrate ${file}: its legacy managed block is malformed."
  fi
}

validate_home_manager_migration() {
  validate_home_manager_file "${HOME}/.zshenv" "startup"
  validate_home_manager_file "${HOME}/.config/starship.toml" "config"
  validate_legacy_fontconfig
  if [[ "$IS_WSL" -eq 0 ]]; then
    validate_home_manager_file "${HOME}/.config/ghostty/config" "config"
  fi
}

backup_home_manager_path() {
  local file="$1"
  local copy=""

  if [[ -e "$file" || -L "$file" ]]; then
    copy="${HOME_MANAGER_MIGRATION_BACKUP}/${#HOME_MANAGER_MIGRATION_PATHS[@]}"
    cp -a "$file" "$copy"
  fi
  HOME_MANAGER_MIGRATION_PATHS+=("$file")
  HOME_MANAGER_MIGRATION_COPIES+=("$copy")
}

begin_home_manager_migration() {
  HOME_MANAGER_MIGRATION_BACKUP="$(mktemp -d)" \
    || fail "Failed to create Home Manager migration backup."
  HOME_MANAGER_MIGRATION_PATHS=()
  HOME_MANAGER_MIGRATION_COPIES=()

  backup_home_manager_path "${HOME}/.zshenv"
  backup_home_manager_path "${HOME}/.config/starship.toml"
  backup_home_manager_path "${HOME}/.config/fontconfig/fonts.conf"
  if [[ "$IS_WSL" -eq 0 ]]; then
    backup_home_manager_path "${HOME}/.config/ghostty/config"
  fi
}

prepare_home_manager_file() {
  local file="$1"
  local legacy_block="$2"

  validate_home_manager_file "$file" "$legacy_block"
  [[ -e "$file" || -L "$file" ]] || return 0
  home_manager_owned_symlink "$file" && return 0
  rm -f "$file"
}

remove_legacy_fontconfig_block() {
  local file="${HOME}/.config/fontconfig/fonts.conf"
  local start="<!-- >>> ${SCRIPT_MARKER}:nix-profile-fonts -->"
  local end="<!-- <<< ${SCRIPT_MARKER}:nix-profile-fonts -->"
  local tmp

  [[ -f "$file" ]] || return 0
  grep -Fq "$start" "$file" || return 0

  tmp="$(mktemp)" || fail "Failed to create temporary file"
  awk -v start="$start" -v end="$end" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    !in_block { print }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

prepare_home_manager_migration() {
  validate_home_manager_migration
  begin_home_manager_migration
  prepare_home_manager_file "${HOME}/.zshenv" "startup"
  prepare_home_manager_file "${HOME}/.config/starship.toml" "config"
  remove_legacy_fontconfig_block
  if [[ "$IS_WSL" -eq 0 ]]; then
    prepare_home_manager_file "${HOME}/.config/ghostty/config" "config"
  fi
}

restore_home_manager_migration() {
  local index
  local file
  local copy

  for ((index = 0; index < ${#HOME_MANAGER_MIGRATION_PATHS[@]}; index++)); do
    file="${HOME_MANAGER_MIGRATION_PATHS[$index]}"
    copy="${HOME_MANAGER_MIGRATION_COPIES[$index]}"
    rm -f "$file"
    if [[ -n "$copy" ]]; then
      mkdir -p "$(dirname "$file")"
      cp -a "$copy" "$file"
    fi
  done
}

finish_home_manager_migration() {
  if [[ -n "$HOME_MANAGER_MIGRATION_BACKUP" ]]; then
    rm -rf "$HOME_MANAGER_MIGRATION_BACKUP"
  fi
  HOME_MANAGER_MIGRATION_BACKUP=""
  HOME_MANAGER_MIGRATION_PATHS=()
  HOME_MANAGER_MIGRATION_COPIES=()
}

activate_home_manager() (
  local activation_started=0
  local activation_succeeded=0
  local activation_package
  local current_system
  local configuration
  local current_generation_root
  local platform_variant=""
  local previous_generation=""
  local rollback_failed=0

  cleanup_home_manager_activation() {
    local status=$?

    trap - EXIT HUP INT TERM
    if [[ "$activation_succeeded" -eq 0 ]]; then
      if [[ "$activation_started" -eq 1 \
        && -n "$previous_generation" \
        && "$previous_generation" != "$activation_package" ]]
      then
        log "Reactivating the previous Home Manager generation"
        "${previous_generation}/activate" || rollback_failed=1
      fi
      if [[ -n "$HOME_MANAGER_MIGRATION_BACKUP" ]]; then
        restore_home_manager_migration
      fi
    fi
    finish_home_manager_migration

    if [[ "$rollback_failed" -eq 1 ]]; then
      printf '[home-manager] Previous generation rollback failed.\n' >&2
    fi
    exit "$status"
  }

  current_system="$(nix eval --impure --raw --expr builtins.currentSystem)"
  if [[ "$IS_WSL" -eq 1 ]]; then
    platform_variant="-wsl"
  fi
  configuration="${HOME_MANAGER_USER}@${current_system}${platform_variant}"

  log "Building Home Manager configuration ${configuration}"
  activation_package="$(
    nix build \
      --no-link \
      --print-out-paths \
      "${FLAKE_URL}#homeConfigurations.\"${configuration}\".activationPackage"
  )"
  [[ -x "${activation_package}/activate" ]] \
    || fail "Home Manager activation package is missing its activate command."

  current_generation_root="${XDG_STATE_HOME:-${HOME}/.local/state}/home-manager/gcroots/current-home"
  if [[ -L "$current_generation_root" ]]; then
    previous_generation="$(readlink "$current_generation_root" 2>/dev/null || true)"
    [[ -x "${previous_generation}/activate" ]] || previous_generation=""
  fi

  trap cleanup_home_manager_activation EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  prepare_home_manager_migration
  log "Activating Home Manager configuration"
  activation_started=1
  if ! "${activation_package}/activate"; then
    fail "Home Manager activation failed; restoring the previous user configuration."
  fi
  activation_succeeded=1
)
