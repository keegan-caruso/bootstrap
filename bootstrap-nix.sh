#!/usr/bin/env bash
set -euo pipefail

GIT_NAME="Keegan Caruso"
SCRIPT_MARKER="codex-dev-shell"
IS_WSL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FLAKE_DIR="${SCRIPT_DIR}/nix"
FLAKE_URL="path:${FLAKE_DIR}"
STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
PROFILE_PATH="${STATE_HOME}/nix/profiles/bootstrap"
HOME_MANAGER_USER="keegancaruso"
SUBUID_FILE="${SUBUID_FILE:-/etc/subuid}"
SUBGID_FILE="${SUBGID_FILE:-/etc/subgid}"
NIX_INSTALLER_VERSION="v3.23.2"
NIX_INSTALLER_SHA256="7dad70f7ea368a3cad732ea40ae4e67909394c87ee4d218ab29368f4796d2486"
NIX_INSTALLER_URL="https://github.com/DeterminateSystems/nix-installer/releases/download/${NIX_INSTALLER_VERSION}/nix-installer.sh"
AZUREAUTH_VERSION="0.9.6"
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
# shellcheck source=lib/home-manager.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/home-manager.sh"
# shellcheck source=lib/shell-config.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/shell-config.sh"

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

detect_os() {
  case "$(uname -s)" in
    Darwin)
      [[ "$(uname -m)" == "arm64" ]] \
        || fail "Intel macOS is not supported by the pinned nixpkgs revision."
      OS="macos"
      ;;
    Linux)
      local os_release="${OS_RELEASE_FILE:-/etc/os-release}"
      [[ -f "$os_release" ]] || fail "Unable to detect Linux distribution."
      # shellcheck disable=SC1090
      . "$os_release"
      case "${ID:-}" in
        ubuntu)
          OS="ubuntu"
          ;;
        fedora)
          [[ "${VERSION_ID:-}" == "45" ]] \
            || fail "Unsupported Fedora version: ${VERSION_ID:-unknown}. This script supports Fedora 45."
          [[ ! -e /run/ostree-booted ]] \
            || fail "Fedora Atomic desktops are not supported by this bootstrap."
          OS="fedora"
          ;;
        *)
          fail "Unsupported Linux distribution: ${ID:-unknown}. This script supports Ubuntu and Fedora."
          ;;
      esac
      if is_wsl; then
        [[ "$OS" == "ubuntu" ]] || fail "WSL bootstrap supports Ubuntu only."
        IS_WSL=1
      fi
      ;;
    *)
      fail "Unsupported operating system: $(uname -s)"
      ;;
  esac
}

require_sudo() {
  [[ "$OS" == "ubuntu" || "$OS" == "fedora" ]] || return 0
  command_exists sudo || fail "sudo is required on Linux."
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
# Inotify limits for editors, language servers, tsc --watch, etc.
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
  if ! sudo sysctl --quiet --load="$conf" 2>/dev/null; then
    log "sysctl --load failed; settings will apply after 'wsl --shutdown'"
  fi
}

find_subordinate_id_start() {
  local file="$1"
  local candidate=100000
  local count=65536

  while sudo awk -F: \
    -v start="$candidate" \
    -v end="$((candidate + count - 1))" '
      NF >= 3 {
        range_start = $2
        range_end = $2 + $3 - 1
        if (start <= range_end && end >= range_start) {
          found = 1
          exit
        }
      }
      END { exit found ? 0 : 1 }
    ' "$file"
  do
    candidate=$((candidate + count))
  done

  printf '%s\n' "$candidate"
}

ensure_subordinate_id_range() {
  local file="$1"
  local usermod_option="$2"
  local label="$3"
  local user="$4"
  local start

  if sudo awk -F: -v user="$user" '
    $1 == user && $3 >= 65536 { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$file"; then
    log "Rootless container ${label} range already configured for ${user}"
    return
  fi

  start="$(find_subordinate_id_start "$file")"
  log "Allocating rootless container ${label} range for ${user}"
  sudo usermod "$usermod_option" "${start}-$((start + 65535))" "$user"
}

ensure_rootless_container_prereqs() {
  [[ "$OS" == "ubuntu" ]] || return 0

  local user
  local sysctl_conf="/etc/sysctl.d/99-${SCRIPT_MARKER}-containers.conf"
  local sysctl_settings=""

  user="$(id -un)"
  ensure_subordinate_id_range "$SUBUID_FILE" --add-subuids "UID" "$user"
  ensure_subordinate_id_range "$SUBGID_FILE" --add-subgids "GID" "$user"

  [[ -u /usr/bin/newuidmap ]] \
    || fail "/usr/bin/newuidmap must be setuid root for rootless containers."
  [[ -u /usr/bin/newgidmap ]] \
    || fail "/usr/bin/newgidmap must be setuid root for rootless containers."

  if [[ -e /proc/sys/kernel/unprivileged_userns_clone ]] \
    && [[ "$(< /proc/sys/kernel/unprivileged_userns_clone)" != "1" ]]; then
    sysctl_settings+="kernel.unprivileged_userns_clone = 1"$'\n'
  fi
  if [[ -e /proc/sys/user/max_user_namespaces ]] \
    && (( $(< /proc/sys/user/max_user_namespaces) == 0 )); then
    sysctl_settings+="user.max_user_namespaces = 28633"$'\n'
  fi

  if [[ -n "$sysctl_settings" ]]; then
    log "Enabling unprivileged user namespaces for rootless containers"
    printf '# Managed by %s. Rootless container user namespaces.\n%s' \
      "$SCRIPT_MARKER" "$sysctl_settings" \
      | sudo tee "$sysctl_conf" >/dev/null
    sudo sysctl --quiet --load="$sysctl_conf"
  fi
}

install_host_prereqs() {
  case "$OS" in
    ubuntu)
      log "Installing Ubuntu integration prerequisites"
      sudo apt-get update
      sudo apt-get install -y \
        ca-certificates \
        curl \
        gnome-keyring \
        '?name(^libicu[0-9]+$)' \
        libsecret-1-0 \
        libsecret-tools \
        uidmap \
        xz-utils
      ;;
    fedora)
      log "Installing Fedora integration prerequisites"
      sudo dnf install -y \
        ca-certificates \
        /usr/bin/curl \
        gnome-keyring \
        libsecret \
        policycoreutils \
        util-linux \
        xz
      ;;
  esac
}

install_azureauth() {
  [[ "$IS_WSL" -eq 1 ]] || return 0

  local arch checksum package actual_checksum staging
  local install_root="${HOME}/.local/share/azureauth/${AZUREAUTH_VERSION}"
  local binary="${install_root}/azureauth"
  local link="${HOME}/.local/bin/azureauth"
  if [[ "$(dpkg-query -W -f='${Version}' azureauth 2>/dev/null)" == "${AZUREAUTH_VERSION}-1" ]]; then
    return
  fi
  if [[ -L "$link" && "$(readlink "$link")" == "$binary" && -x "$binary" ]]; then
    return
  fi
  [[ ! -e "$link" && ! -L "$link" ]] \
    || fail "Cannot replace an existing AzureAuth executable at ${link}."
  [[ ! -e "$install_root" ]] \
    || fail "AzureAuth installation at ${install_root} is incomplete."

  case "$(uname -m)" in
    x86_64)
      arch="x64"
      checksum="3943ffeba55b380c087d8f92a3221caf8b1c02c198558d472613248169639b45"
      ;;
    aarch64)
      arch="arm64"
      checksum="e19df4a0bb59bbe4deb7a4e45aed50ff229b78d5248501fc73d9b626335338e8"
      ;;
    *)
      fail "Unsupported AzureAuth architecture: $(uname -m)"
      ;;
  esac

  package="$(mktemp --suffix=.deb)" || fail "Failed to create AzureAuth package file"
  if ! curl --proto '=https' --tlsv1.2 -fsSL \
    "https://github.com/AzureAD/microsoft-authentication-cli/releases/download/${AZUREAUTH_VERSION}/azureauth-${AZUREAUTH_VERSION}-linux-${arch}.deb" \
    -o "$package"; then
    rm -f "$package"
    fail "Failed to download AzureAuth ${AZUREAUTH_VERSION}"
  fi
  actual_checksum="$(sha256sum "$package" | awk '{ print $1 }')"
  if [[ "$actual_checksum" != "$checksum" ]]; then
    rm -f "$package"
    fail "AzureAuth package checksum verification failed"
  fi
  mkdir -p "${HOME}/.local/share/azureauth" "${HOME}/.local/bin"
  staging="$(mktemp -d "${HOME}/.local/share/azureauth/.${AZUREAUTH_VERSION}.XXXXXX")" \
    || fail "Failed to create AzureAuth installation directory"
  if ! dpkg-deb -x "$package" "$staging"; then
    rm -rf "$staging"
    rm -f "$package"
    fail "Failed to extract AzureAuth ${AZUREAUTH_VERSION}"
  fi
  rm -f "$package"
  mv "${staging}/usr/lib/azureauth" "$install_root"
  rm -rf "$staging"
  ln -s "$binary" "$link"
}

install_nix() {
  if command_exists nix; then
    log "Nix is already installed"
    return
  fi

  local installer
  local actual_sha256

  installer="$(mktemp)" || fail "Failed to create temporary installer file"

  log "Downloading Determinate Nix installer ${NIX_INSTALLER_VERSION}"
  if ! curl --proto '=https' --tlsv1.2 -sSfL \
    "$NIX_INSTALLER_URL" \
    -o "$installer"
  then
    rm -f "$installer"
    fail "Failed to download Determinate Nix installer ${NIX_INSTALLER_VERSION}"
  fi

  if command_exists sha256sum; then
    actual_sha256="$(sha256sum "$installer" | awk '{ print $1 }')"
  elif command_exists shasum; then
    actual_sha256="$(shasum -a 256 "$installer" | awk '{ print $1 }')"
  else
    rm -f "$installer"
    fail "A SHA-256 checksum tool is required (sha256sum or shasum)"
  fi

  if [[ "$actual_sha256" != "$NIX_INSTALLER_SHA256" ]]; then
    rm -f "$installer"
    fail "Determinate Nix installer checksum verification failed"
  fi

  log "Installing Nix (Determinate Systems installer, multi-user, flakes enabled)"
  if ! sh "$installer" install --no-confirm; then
    rm -f "$installer"
    fail "Determinate Nix installer failed"
  fi

  rm -f "$installer"
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
  local current_system
  local desired_attr
  local output_name
  local profile_ref

  output_name="$(nix_tool_output "$IS_WSL")"
  profile_ref="${FLAKE_URL}#${output_name}"
  current_system="$(nix eval --impure --raw --expr builtins.currentSystem)"
  desired_attr="packages.${current_system}.${output_name}"

  log "Building development tools from ${profile_ref}"
  nix build --no-link "$profile_ref"

  mkdir -p "$(dirname "$PROFILE_PATH")"
  update_dev_tools_profile "$profile_ref" "$desired_attr"
  export PATH="${PROFILE_PATH}/bin:${PATH}"
}

install_wsl_browser_link() {
  [[ "$IS_WSL" -eq 1 ]] || return 0

  local xdg_open="${HOME}/.local/bin/xdg-open"

  if [[ ! -e "$xdg_open" && ! -L "$xdg_open" ]]; then
    ln -s "${HOME}/.local/bin/wsl-browser" "$xdg_open"
  fi
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

remove_legacy_tool_installations() {
  local legacy_csharpier="${HOME}/.local/bin/csharpier"
  local legacy_dotnet="${HOME}/.dotnet"
  local legacy_installer="${XDG_CACHE_HOME:-${HOME}/.cache}/${SCRIPT_MARKER}/dotnet-install.sh"
  local csharpier_target

  if [[ -L "$legacy_csharpier" ]]; then
    csharpier_target="$(readlink "$legacy_csharpier")"
    if [[ "$csharpier_target" == "${legacy_dotnet}/tools/csharpier" ]]; then
      log "Removing legacy CSharpier shim"
      rm -f "$legacy_csharpier"
    fi
  fi

  if [[ -f "$legacy_installer" ]]; then
    rm -f "$legacy_installer"
    rmdir "$(dirname "$legacy_installer")" 2>/dev/null || true
  fi

  if [[ "${BOOTSTRAP_REMOVE_LEGACY_DOTNET:-0}" == "1" && -d "$legacy_dotnet" ]]; then
    log "Removing legacy bootstrap-managed .NET installation"
    rm -rf "$legacy_dotnet"
  elif [[ -d "$legacy_dotnet" ]] && rmdir "$legacy_dotnet" 2>/dev/null; then
    log "Removing empty legacy .NET installation directory"
  elif [[ -d "$legacy_dotnet" ]]; then
    log "Leaving ${legacy_dotnet}; set BOOTSTRAP_REMOVE_LEGACY_DOTNET=1 to remove it"
  fi
}

link_nix_apps() {
  [[ "$OS" == "macos" ]] || return 0
  [[ -d "${PROFILE_PATH}/Applications" ]] || return 0

  local app
  mkdir -p "${HOME}/Applications"
  for app in "${PROFILE_PATH}/Applications/"*.app; do
    [[ -e "$app" ]] || continue
    ln -sfn "$app" "${HOME}/Applications/${app##*/}"
  done
}

remove_homebrew_shell_config() {
  remove_block "${HOME}/.zprofile" "homebrew"
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

remove_wsl_credential_helper() {
  if git config --global --get-all credential.helper | grep -Fxq manager-wsl; then
    git config --global --unset-all credential.helper '^manager-wsl$'
  fi
  if git config --global --get-all credential.https://dev.azure.com.helper | grep -Fxq manager-wsl; then
    git config --global --unset-all credential.https://dev.azure.com.helper '^manager-wsl$'
  fi
}

configure_git() {
  local key
  local managed_config="${HOME}/.config/git/bootstrap.config"

  log "Configuring global Git settings"
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"

  for key in \
    core.pager \
    interactive.diffFilter \
    delta.light \
    delta.navigate \
    delta.line-numbers \
    delta.side-by-side \
    merge.conflictStyle \
    fetch.prune \
    init.defaultBranch
  do
    git config --global --unset-all "$key" || true
  done
  git config --global --unset-all include.path "$managed_config" || true
  git config --global --add include.path "$managed_config"

  if [[ "$IS_WSL" -eq 1 ]]; then
    git config --global core.fileMode false
    git config --global core.autocrlf input
    command_exists "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe" \
      || fail "Windows Git Credential Manager is required. Install Git for Windows first."
    remove_wsl_credential_helper
    git config --global --replace-all credential.helper \
      '/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe'
    git config --global credential.https://dev.azure.com.useHttpPath true
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
  ' "${FLAKE_DIR}/templates/jj/config.toml.tmpl")"

  upsert_block "$jj_config" "config" "$jj_block"
}

main() {
  detect_os
  configure_shell_profile
  require_sudo

  if [[ "$IS_WSL" -eq 1 ]]; then
    ensure_wsl_interop
    ensure_wsl_systemd
    ensure_ipv4_precedence
    ensure_dev_sysctls
  fi

  install_host_prereqs
  install_azureauth
  ensure_rootless_container_prereqs
  install_nix
  source_nix
  install_dev_tools
  install_dotnet_tools
  install_node_tools
  activate_home_manager
  install_wsl_browser_link
  link_nix_apps
  prompt_for_git_email
  remove_homebrew_shell_config
  reconcile_shell_loaders
  configure_git
  write_jj_config
  remove_legacy_profile_entries
  remove_legacy_tool_installations

  log "Nix bootstrap complete"
  log "Open a new shell or run: source ~/.zshrc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
