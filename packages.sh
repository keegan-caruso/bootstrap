#!/usr/bin/env bash
# shellcheck disable=SC2034

ARTIFACTS_NPM_REGISTRY="https://pkgs.dev.azure.com/artifacts-public/23934c1b-a3b5-4b70-9dd3-d1bef4cc72a0/_packaging/AzureArtifacts/npm/registry/"

MICROSOFT_NPM_GLOBAL_PACKAGES=(
  @microsoft/artifacts-npm-credprovider@1.1.4
)

NPM_GLOBAL_PACKAGES=(
  markdownlint-cli2@0.23.2
  oxfmt@0.66.0
  oxlint@1.81.0
  typescript@7.0.2
)
