#!/usr/bin/env bash
# shellcheck disable=SC2034

ARTIFACTS_NPM_REGISTRY="https://pkgs.dev.azure.com/artifacts-public/23934c1b-a3b5-4b70-9dd3-d1bef4cc72a0/_packaging/AzureArtifacts/npm/registry/"
NUGET_PUBLIC_SOURCE="https://api.nuget.org/v3/index.json"
NUGET_CREDENTIAL_PROVIDER_PACKAGE="Microsoft.Artifacts.CredentialProvider.NuGet.Tool"
NUGET_CREDENTIAL_PROVIDER_VERSION="2.0.5"

MICROSOFT_NPM_GLOBAL_PACKAGES=(
  @microsoft/artifacts-npm-credprovider@1.2.1
)

NPM_GLOBAL_PACKAGES=(
  markdownlint-cli2@0.23.3
  oxfmt@0.73.0
  oxlint@1.88.0
  typescript@7.0.2
)
