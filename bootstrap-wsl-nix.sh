#!/usr/bin/env bash
set -euo pipefail

GIT_NAME="Keegan Caruso"
SCRIPT_MARKER="codex-dev-shell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="${SCRIPT_DIR}/nix"
PROFILE_REF="path:${FLAKE_DIR}#default"

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

detect_wsl_ubuntu() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    fail "This script runs on WSL Ubuntu only."
  fi

  if [[ ! -f /etc/os-release ]]; then
    fail "Unable to detect Linux distribution."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "Unsupported Linux distribution: ${ID:-unknown}. This script supports Ubuntu only."
  fi

  if [[ -z "${WSL_DISTRO_NAME:-}" && -z "${WSL_INTEROP:-}" ]] \
    && ! grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
    fail "WSL not detected. Use bootstrap-dev-shell.sh for native Linux."
  fi
}

require_sudo() {
  if ! command_exists sudo; then
    fail "sudo is required."
  fi
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
# Bumps inotify limits for VS Code, language servers, tsc --watch, etc.,
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
  log "Installing minimal apt prerequisites (curl, ca-certificates, xz-utils, zsh)"
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates xz-utils zsh
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
  log "Installing WSL dev tools from ${PROFILE_REF}"

  local add_cmd=(nix profile add)
  if ! nix profile add --help >/dev/null 2>&1; then
    add_cmd=(nix profile install)
  fi

  local out
  if out="$("${add_cmd[@]}" "$PROFILE_REF" 2>&1)"; then
    printf '%s\n' "$out"
    return
  fi

  printf '%s\n' "$out"

  if printf '%s\n' "$out" | grep -qiE 'already (installed|exists|added)|conflict'; then
    log "Profile already contains an entry for this flake; attempting upgrade"
    if ! nix profile upgrade '.*wsl-dev-tools.*' 2>&1; then
      log "Could not auto-upgrade. Run 'nix profile list' and then"
      log "  nix profile upgrade <index>  (or)  nix profile remove <index> && rerun"
    fi
    return
  fi

  fail "nix profile install failed"
}

register_nix_profile_fonts() {
  local fonts_conf_dir="${HOME}/.config/fontconfig"
  local fonts_conf="${fonts_conf_dir}/fonts.conf"
  local profile_fonts="${HOME}/.nix-profile/share/fonts"
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

write_zshrc_blocks() {
  local zshrc="${HOME}/.zshrc"
  upsert_block "$zshrc" "path" "$(read_template "${SCRIPT_DIR}/templates/zsh/path.sh")"
  upsert_block "$zshrc" "interactive" "$(read_template "${SCRIPT_DIR}/templates/zsh/interactive.sh")"
  upsert_block "$zshrc" "prompt" "$(read_template "${SCRIPT_DIR}/templates/zsh/prompt.sh")"
  upsert_block "$zshrc" "shell-tools" "$(read_template "${SCRIPT_DIR}/templates/zsh/shell-tools.sh")"
  upsert_block "$zshrc" "syntax-highlighting" "$(read_template "${SCRIPT_DIR}/templates/zsh/syntax-highlighting.sh")"
}

write_bashrc_wsl_block() {
  local bashrc="${HOME}/.bashrc"
  upsert_block "$bashrc" "wsl-zsh-handoff" \
    "$(read_template "${SCRIPT_DIR}/templates/bash/wsl-zsh-handoff.sh")"
}

write_starship_config() {
  local starship_config="${HOME}/.config/starship.toml"
  upsert_block "$starship_config" "config" "$(read_template "${SCRIPT_DIR}/templates/starship.toml")"
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

find_windows_credential_manager() {
  local paths=(
    "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
    "/mnt/c/Program Files/Git/mingw64/libexec/git-core/git-credential-manager.exe"
    "/mnt/c/Program Files (x86)/Git/mingw64/bin/git-credential-manager.exe"
    "/mnt/c/Program Files/Git/mingw64/libexec/git-core/git-credential-manager-core.exe"
  )

  local candidate
  for candidate in "${paths[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  if command_exists git-credential-manager.exe; then
    command -v git-credential-manager.exe
    return
  fi

  return 1
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
  git config --global core.fileMode false
  git config --global core.autocrlf input

  local gcm_path
  if gcm_path="$(find_windows_credential_manager)"; then
    git config --global credential.helper "\"${gcm_path}\""
    log "Git credential helper set to Windows GCM: ${gcm_path}"
  else
    log "Windows Git Credential Manager not found; skipping credential.helper"
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
  detect_wsl_ubuntu
  require_sudo
  ensure_wsl_interop
  ensure_wsl_systemd
  ensure_ipv4_precedence
  ensure_dev_sysctls
  install_apt_prereqs
  install_nix
  source_nix
  install_dev_tools
  register_nix_profile_fonts
  prompt_for_git_email
  write_zshrc_blocks
  write_bashrc_wsl_block
  write_starship_config
  configure_git
  write_jj_config

  log "Nix-based WSL bootstrap complete"
  log "Open a new shell or run: source ~/.zshrc"
  log "The VS Code launcher is out of scope for this script;"
  log "see docs/nix-wsl.md."
}

main "$@"
