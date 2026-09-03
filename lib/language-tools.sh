#!/usr/bin/env bash

install_dotnet_tools() {
  local tool_path="${HOME}/.local/bin"

  command_exists dotnet || fail "dotnet is required to install .NET tools."
  mkdir -p "$tool_path"

  if dotnet tool list --tool-path "$tool_path" \
    | awk 'NR > 2 { print tolower($1) }' \
    | grep -Fxq "${NUGET_CREDENTIAL_PROVIDER_PACKAGE,,}"; then
    log "Updating the Azure Artifacts NuGet credential provider"
    dotnet tool update \
      --tool-path "$tool_path" \
      --version "$NUGET_CREDENTIAL_PROVIDER_VERSION" \
      --source "$NUGET_PUBLIC_SOURCE" \
      "$NUGET_CREDENTIAL_PROVIDER_PACKAGE"
  else
    log "Installing the Azure Artifacts NuGet credential provider"
    dotnet tool install \
      --tool-path "$tool_path" \
      --version "$NUGET_CREDENTIAL_PROVIDER_VERSION" \
      --source "$NUGET_PUBLIC_SOURCE" \
      "$NUGET_CREDENTIAL_PROVIDER_PACKAGE"
  fi
}

install_node_tools() {
  local node_version
  local npm_registry

  if ! command_exists fnm; then
    fail "fnm is required to install Node.js tools."
  fi

  eval "$(fnm env --use-on-cd --shell bash)"

  node_version="$(fnm current 2>/dev/null || true)"
  if [[ ! "$node_version" =~ ^v[0-9]+([.][0-9]+){2}$ ]]; then
    log "Installing Node.js LTS with fnm"
    fnm install --lts --use
    node_version="$(fnm current 2>/dev/null || true)"
  fi

  if [[ ! "$node_version" =~ ^v[0-9]+([.][0-9]+){2}$ ]]; then
    fail "fnm did not provide a managed Node.js runtime."
  fi

  fnm default "$node_version"
  fnm use "$node_version" >/dev/null

  if command_exists corepack; then
    log "Enabling Corepack"
    corepack enable
  fi

  command_exists npm || fail "npm is required after installing Node.js with fnm."
  if [[ -n "${BOOTSTRAP_NPM_REGISTRY:-}" ]]; then
    export NPM_CONFIG_REGISTRY="$BOOTSTRAP_NPM_REGISTRY"
  fi

  npm_registry="$(npm config get registry)"
  [[ -n "$npm_registry" && "$npm_registry" != "undefined" ]] \
    || fail "npm did not resolve a registry from its environment or npmrc files."
  log "Using the registry resolved by npm configuration"

  log "Removing replaced global Node.js tools"
  npm uninstall -g typescript-language-server

  log "Installing global Node.js tools"
  npm install -g \
    --allow-scripts=@microsoft/artifacts-credprovider-wrapper \
    --registry="$ARTIFACTS_NPM_REGISTRY" \
    "${MICROSOFT_NPM_GLOBAL_PACKAGES[@]}"
  npm install -g "${NPM_GLOBAL_PACKAGES[@]}"

  mkdir -p "${HOME}/.local/bin"
  install -m 0755 \
    "${SCRIPT_DIR}/templates/typescript-language-server" \
    "${HOME}/.local/bin/typescript-language-server"
}
