#!/usr/bin/env bash
set -euo pipefail

GIT_NAME="Keegan Caruso"
SCRIPT_MARKER="codex-dev-shell"
IS_WSL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FLAKE_DIR="${SCRIPT_DIR}/nix"
FLAKE_URL="path:${FLAKE_DIR}"
PROFILE_REF="path:${FLAKE_DIR}#default"
WORKSTATION_PROFILE_REF="path:${FLAKE_DIR}#workstation"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
PROFILE_PATH="${STATE_HOME}/nix/profiles/bootstrap"
# shellcheck source=packages.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/packages.sh"
# shellcheck source=lib/nix-profile.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/nix-profile.sh"
# shellcheck source=lib/language-tools.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/language-tools.sh"
# shellcheck source=lib/platform.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/platform.sh"

log() {
  printf '[setup-nix] %s\n' "$*"
}

fail() {
  printf '[setup-nix] %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_wsl_browser() {
  [[ "$IS_WSL" -eq 1 ]] || return

  local local_bin="${HOME}/.local/bin"
  local browser="${local_bin}/wsl-browser"
  local xdg_open="${local_bin}/xdg-open"

  mkdir -p "$local_bin"
  install -m 0755 "${SCRIPT_DIR}/templates/wsl-browser" "$browser"
  if [[ ! -e "$xdg_open" && ! -L "$xdg_open" ]]; then
    ln -s "$browser" "$xdg_open"
  fi
}

read_template() {
  local template_path="$1"

  if [[ ! -f "$template_path" ]]; then
    fail "Template not found: $template_path"
  fi

  cat "$template_path"
}

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

detect_os() {
  case "$(uname -s)" in
    Darwin)
      [[ "$(uname -m)" == "arm64" ]] \
        || fail "Intel macOS is not supported by the pinned nixpkgs revision."
      OS="macos"
      ;;
    Linux)
      [[ -f /etc/os-release ]] || fail "Unable to detect Linux distribution."
      # shellcheck disable=SC1091
      . /etc/os-release
      [[ "${ID:-}" == "ubuntu" ]] \
        || fail "Unsupported Linux distribution: ${ID:-unknown}. This script supports Ubuntu only."
      case "${VERSION_ID:-}" in
        24.04|26.04)
          ;;
        *)
          fail "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. This script supports Ubuntu 24.04 and 26.04."
          ;;
      esac
      OS="ubuntu"
      if is_wsl; then
        IS_WSL=1
      fi
      ;;
    *)
      fail "Unsupported operating system: $(uname -s)"
      ;;
  esac
}

require_sudo() {
  [[ "$OS" == "ubuntu" ]] || return
  command_exists sudo || fail "sudo is required on Ubuntu."
  sudo -v
}

ensure_wsl_interop() {
  local wsl_conf="/etc/wsl.conf"

  if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    log "WSL interop (Windows exe support) is enabled"
    return
  fi

  log "WSL interop is not active; enabling in ${wsl_conf}"

  if [[ ! -f "$wsl_conf" ]] || ! grep -q '^\[interop\]' "$wsl_conf"; then
    printf '\n[interop]\nenabled = true\nappendWindowsPath = true\n' | sudo tee -a "$wsl_conf" >/dev/null
  else
    sudo sed -i '/^\[interop\]/,/^\[/{s/^enabled\s*=.*/enabled = true/}' "$wsl_conf"
    if ! grep -A5 '^\[interop\]' "$wsl_conf" | grep -q '^appendWindowsPath'; then
      sudo sed -i '/^\[interop\]/a appendWindowsPath = true' "$wsl_conf"
    fi
  fi

  log "Restart WSL (wsl --shutdown) to apply interop changes"
}

ensure_ipv4_precedence() {
  local gai_conf="/etc/gai.conf"
  local marker="# ${SCRIPT_MARKER}: prefer IPv4 over IPv6"

  if [[ ! -f "$gai_conf" ]]; then
    log "${gai_conf} not found; skipping IPv4 precedence tweak"
    return
  fi

  if sudo grep -Fq "$marker" "$gai_conf"; then
    log "IPv4 precedence already configured in ${gai_conf}"
    return
  fi

  log "Configuring ${gai_conf} to prefer IPv4 over IPv6 for getaddrinfo()"
  sudo tee -a "$gai_conf" >/dev/null <<EOF

${marker}
# Prefer IPv4 addresses when a host resolves to both IPv4 and IPv6. This
# avoids long IPv6 timeouts on WSL2 when only IPv4 is routable outside the
# local network (e.g. behind a NAT/router that does not understand IPv6),
# while still allowing IPv6 on the local link.
precedence ::ffff:0:0/96  100
# Keep IPv4 NAT/loopback/link-local at the same scope priority as their
# IPv6 equivalents so they get sorted first.
scopev4 ::ffff:169.254.0.0/112  2
scopev4 ::ffff:127.0.0.0/104    2
scopev4 ::ffff:0.0.0.0/96       14
EOF
}

ensure_wsl_systemd() {
  local wsl_conf="/etc/wsl.conf"

  if [[ "$(ps -o comm= 1 2>/dev/null)" == "systemd" ]]; then
    log "systemd already active as PID 1"
    return
  fi

  if [[ -f "$wsl_conf" ]] \
    && awk '/^\[boot\]/{f=1; next} /^\[/{f=0} f' "$wsl_conf" \
       | grep -Eq '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true'; then
    log "systemd already enabled in ${wsl_conf} (run 'wsl --shutdown' if not yet active)"
    return
  fi

  log "Enabling systemd in ${wsl_conf} (run 'wsl --shutdown' for it to take effect)"

  if [[ ! -f "$wsl_conf" ]] || ! grep -q '^\[boot\]' "$wsl_conf"; then
    printf '\n[boot]\nsystemd = true\n' | sudo tee -a "$wsl_conf" >/dev/null
  else
    sudo sed -i -E '/^\[boot\]/,/^\[/{ /^[[:space:]]*systemd[[:space:]]*=/d }' "$wsl_conf"
    sudo sed -i '/^\[boot\]/a systemd = true' "$wsl_conf"
  fi
}

ensure_dev_sysctls() {
  local conf="/etc/sysctl.d/99-${SCRIPT_MARKER}.conf"

  log "Writing editor/watcher sysctl defaults to ${conf}"
  sudo tee "$conf" >/dev/null <<EOF
# Managed by ${SCRIPT_MARKER}. Editor / file-watcher friendly defaults.
# Bumps inotify limits for editors, language servers, tsc --watch, etc.,
# and raises vm.max_map_count for bundlers and JVM/search tooling.
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
vm.max_map_count = 262144
EOF
  if ! sudo sysctl --quiet --load="$conf" 2>/dev/null; then
    log "sysctl --load failed; settings will apply after 'wsl --shutdown'"
  fi
}

install_apt_prereqs() {
  [[ "$OS" == "ubuntu" ]] || return

  log "Installing Ubuntu integration prerequisites"
  sudo apt-get update
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnome-keyring \
    libsecret-1-0 \
    libsecret-tools \
    xz-utils
}

install_nix() {
  if command_exists nix; then
    log "Nix is already installed"
    return
  fi

  log "Installing Nix (Determinate Systems installer, multi-user, flakes enabled)"
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
}

source_nix() {
  local candidates=(
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  )

  if command_exists nix; then
    return
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -r "$candidate" ]]; then
      # shellcheck disable=SC1090
      . "$candidate"
      break
    fi
  done

  if ! command_exists nix; then
    fail "nix not on PATH after install; open a new shell and rerun."
  fi
}

install_dev_tools() {
  local profile_ref="$PROFILE_REF"
  local current_system
  local desired_attr
  local output_name

  if [[ "$IS_WSL" -eq 0 ]]; then
    profile_ref="$WORKSTATION_PROFILE_REF"
  fi

  output_name="${profile_ref##*#}"
  current_system="$(nix eval --impure --raw --expr builtins.currentSystem)"
  desired_attr="packages.${current_system}.${output_name}"

  log "Building development tools from ${profile_ref}"
  nix build --no-link "$profile_ref"

  mkdir -p "$(dirname "$PROFILE_PATH")"
  update_dev_tools_profile "$profile_ref" "$desired_attr"
  export PATH="${PROFILE_PATH}/bin:${PATH}"
}

update_dev_tools_profile() (
  local profile_ref="$1"
  local desired_attr="$2"
  local profile_entries=""
  local staging_profile=""
  local status=0

  acquire_nix_profile_lock "$PROFILE_PATH"
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap '
    status=$?
    [[ -z "$staging_profile" ]] || remove_profile_links "$staging_profile"
    release_nix_profile_lock
    exit "$status"
  ' EXIT

  remove_abandoned_profile_staging "$PROFILE_PATH"
  if [[ -e "$PROFILE_PATH" || -L "$PROFILE_PATH" ]]; then
    profile_entries="$(
      nix profile list --profile "$PROFILE_PATH" | awk '
        /^Flake attribute:/ { attr = $3 }
        /^Original flake URL:/ {
          url = $0
          sub(/^Original flake URL:[[:space:]]*/, "", url)
          print attr "\t" url
        }
      '
    )"
  fi

  if [[ "$profile_entries" == "${desired_attr}"$'\t'"${FLAKE_URL}" ]]; then
    log "Atomically upgrading the bootstrap Nix profile"
    nix profile upgrade --profile "$PROFILE_PATH" --all
  else
    staging_profile="${PROFILE_PATH}.staging.$$"
    remove_profile_links "$staging_profile"
    log "Building a replacement bootstrap Nix profile"
    if ! nix profile add --profile "$staging_profile" "$profile_ref"; then
      return 1
    fi
    if ! nix-env --profile "$PROFILE_PATH" --set "$staging_profile"; then
      return 1
    fi
  fi
)

remove_legacy_profile_entries() {
  local legacy_store_path
  local legacy_store_paths

  legacy_store_paths="$(
    nix profile list 2>/dev/null | awk -v url="path:${FLAKE_DIR}" '
      /^Original flake URL:/ { matches = ($4 == url) }
      matches && /^Store paths:/ {
        for (i = 3; i <= NF; i++) print $i
      }
    '
  )"
  while IFS= read -r legacy_store_path; do
    [[ -n "$legacy_store_path" ]] || continue
    log "Removing legacy shared-profile entry"
    nix profile remove "$legacy_store_path"
  done <<<"$legacy_store_paths"
}

register_nix_profile_fonts() {
  if [[ "$OS" == "macos" ]]; then
    local mac_fonts="${HOME}/Library/Fonts/Nix"
    [[ -d "${PROFILE_PATH}/share/fonts" ]] || return
    mkdir -p "$mac_fonts"
    find -L "${PROFILE_PATH}/share/fonts" -type f \
      \( -name '*.otf' -o -name '*.ttf' \) \
      -exec cp -f {} "$mac_fonts/" \;
    return
  fi

  local fonts_conf_dir="${HOME}/.config/fontconfig"
  local fonts_conf="${fonts_conf_dir}/fonts.conf"
  local profile_fonts="${PROFILE_PATH}/share/fonts"
  local snippet
  local marker_start="<!-- >>> ${SCRIPT_MARKER}:nix-profile-fonts -->"
  local marker_end="<!-- <<< ${SCRIPT_MARKER}:nix-profile-fonts -->"

  if [[ ! -d "$profile_fonts" ]]; then
    log "No fonts directory at ${profile_fonts}; skipping fontconfig registration"
    return
  fi

  mkdir -p "$fonts_conf_dir"

  if [[ ! -f "$fonts_conf" ]]; then
    cat >"$fonts_conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
${marker_start}
<dir>${profile_fonts}</dir>
${marker_end}
</fontconfig>
EOF
  elif ! grep -Fq "$marker_start" "$fonts_conf"; then
    snippet="${marker_start}\n<dir>${profile_fonts}</dir>\n${marker_end}"
    if grep -Fq "</fontconfig>" "$fonts_conf"; then
      # Insert before the closing </fontconfig> tag.
      awk -v block="$snippet" '
        /<\/fontconfig>/ && !done {
          n = split(block, lines, "\n")
          for (i = 1; i <= n; i++) print lines[i]
          done = 1
        }
        { print }
      ' "$fonts_conf" >"${fonts_conf}.tmp"
      mv "${fonts_conf}.tmp" "$fonts_conf"
    else
      printf '%s\n<dir>%s</dir>\n%s\n' "$marker_start" "$profile_fonts" "$marker_end" >>"$fonts_conf"
    fi
  fi

  if command_exists fc-cache; then
    log "Refreshing fontconfig cache for ${profile_fonts}"
    fc-cache -f "$profile_fonts" >/dev/null 2>&1 || true
  else
    log "fc-cache not on PATH; new fonts will be picked up on next fontconfig scan"
  fi
}

link_nix_apps() {
  [[ "$OS" == "macos" ]] || return
  [[ -d "${PROFILE_PATH}/Applications" ]] || return

  local app
  mkdir -p "${HOME}/Applications"
  for app in "${PROFILE_PATH}/Applications/"*.app; do
    [[ -e "$app" ]] || continue
    ln -sfn "$app" "${HOME}/Applications/${app##*/}"
  done
}

write_zshrc_blocks() {
  local zshrc="${HOME}/.zshrc"
  upsert_block "$zshrc" "path" "$(read_template "${SCRIPT_DIR}/templates/zsh/path.sh")"
  upsert_block "$zshrc" "interactive" "$(read_template "${SCRIPT_DIR}/templates/zsh/interactive.sh")"
  upsert_block "$zshrc" "prompt" "$(read_template "${SCRIPT_DIR}/templates/zsh/prompt.sh")"
  upsert_block "$zshrc" "shell-tools" "$(read_template "${SCRIPT_DIR}/templates/zsh/shell-tools.sh")"
  upsert_block "$zshrc" "syntax-highlighting" "$(read_template "${SCRIPT_DIR}/templates/zsh/syntax-highlighting.sh")"
}

write_zshenv_block() {
  upsert_block "${HOME}/.zshenv" "startup" \
    "$(read_template "${SCRIPT_DIR}/templates/zsh/zshenv.sh")"
}

remove_homebrew_shell_config() {
  remove_block "${HOME}/.zprofile" "homebrew"
}

write_bashrc_blocks() {
  [[ "$IS_WSL" -eq 1 ]] || return

  upsert_block "${HOME}/.bashrc" "aliases" \
    "$(read_template "${SCRIPT_DIR}/templates/bash/aliases.sh")"
}

write_starship_config() {
  local starship_config="${HOME}/.config/starship.toml"
  upsert_block "$starship_config" "config" "$(read_template "${SCRIPT_DIR}/templates/starship.toml")"
}

write_ghostty_config() {
  [[ "$IS_WSL" -eq 0 ]] || return

  local ghostty_config="${HOME}/.config/ghostty/config"
  upsert_block "$ghostty_config" "config" \
    "$(read_template "${SCRIPT_DIR}/templates/ghostty/config")"
}

prompt_for_git_email() {
  local input

  while true; do
    read -r -p "GitHub email: " input
    if [[ -n "$input" ]]; then
      GIT_EMAIL="$input"
      return
    fi
    printf 'Email is required.\n'
  done
}

configure_gcm_wsl_credential_helper() {
  local host key
  local helper="${HOME}/.local/bin/git-credential-manager-wsl"

  command_exists git.exe \
    || fail "Git for Windows is required for brokered Git authentication."

  mkdir -p "${HOME}/.local/bin"
  install -m 0755 "${SCRIPT_DIR}/templates/git-credential-manager-wsl" "$helper"

  git config --global credential.helper manager-wsl
  for host in github.com gist.github.com; do
    key="credential.https://${host}.helper"
    if git config --global --get-all "$key" >/dev/null; then
      git config --global --unset-all "$key"
    fi
  done

  git config --global credential.https://dev.azure.com.useHttpPath true
  git.exe config --global credential.msauthUseBroker true

  log "Git credential helper set to Windows GCM through the native WSL wrapper"
}

configure_git() {
  log "Configuring global Git settings"
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.light true
  git config --global delta.navigate true
  git config --global delta.line-numbers true
  git config --global delta.side-by-side true
  git config --global merge.conflictStyle zdiff3
  git config --global fetch.prune true
  git config --global init.defaultBranch main

  if [[ "$IS_WSL" -eq 1 ]]; then
    git config --global core.fileMode false
    git config --global core.autocrlf input
    configure_gcm_wsl_credential_helper
  fi
}

write_jj_config() {
  local jj_config="${HOME}/.config/jj/config.toml"
  local jj_block

  jj_block="$(awk -v git_name="$GIT_NAME" -v git_email="$GIT_EMAIL" '
    {
      gsub(/__GIT_NAME__/, git_name)
      gsub(/__GIT_EMAIL__/, git_email)
      print
    }
  ' "${SCRIPT_DIR}/templates/jj/config.toml.tmpl")"

  upsert_block "$jj_config" "config" "$jj_block"
}

main() {
  detect_os
  require_sudo

  if [[ "$IS_WSL" -eq 1 ]]; then
    ensure_wsl_interop
    ensure_wsl_systemd
    ensure_ipv4_precedence
    ensure_dev_sysctls
  fi

  install_apt_prereqs
  install_nix
  source_nix
  install_dev_tools
  install_node_tools
  register_nix_profile_fonts
  link_nix_apps
  install_wsl_browser
  prompt_for_git_email
  remove_homebrew_shell_config
  write_zshenv_block
  write_zshrc_blocks
  if [[ "$IS_WSL" -eq 1 ]]; then
    remove_block "${HOME}/.bashrc" "wsl-zsh-handoff"
    write_bashrc_blocks
  fi
  write_starship_config
  write_ghostty_config
  configure_git
  write_jj_config
  remove_legacy_profile_entries

  log "Nix bootstrap complete"
  log "Open a new shell or run: source ~/.zshrc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
