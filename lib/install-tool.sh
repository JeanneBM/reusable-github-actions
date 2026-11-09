#!/usr/bin/env bash
# Install a pinned tool release after verifying its SHA-256, and put it on PATH.
# Nothing downloaded is executed before the checksum matches.
#
# Usage: install-tool.sh TOOL [VERSION SHA256]
#   TOOL     trivy | cosign | gitleaks
#   VERSION  exact release without the leading v; defaults to lib/versions.env
#   SHA256   required whenever VERSION is given
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source-path=SCRIPTDIR source=versions.env
source "$here/versions.env"

tool=${1:?tool required: trivy, cosign or gitleaks}
version=${2:-}
sha256=${3:-}

case "$tool" in
  trivy)    pinned_version=$TRIVY_VERSION;    pinned_sha=$TRIVY_SHA256 ;;
  cosign)   pinned_version=$COSIGN_VERSION;   pinned_sha=$COSIGN_SHA256 ;;
  gitleaks) pinned_version=$GITLEAKS_VERSION; pinned_sha=$GITLEAKS_SHA256 ;;
  *) echo "::error::unknown tool '$tool'"; exit 1 ;;
esac

if [[ -z "$version" ]]; then
  version=$pinned_version
  sha256=${sha256:-$pinned_sha}
elif [[ -z "$sha256" ]]; then
  echo "::error::$tool $version: pass sha256 together with version (from the release checksums file)"
  exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::$tool: version must be an exact release such as $pinned_version; 'latest' is not accepted"
  exit 1
fi
if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "::error::$tool: sha256 must be 64 lowercase hex characters"
  exit 1
fi

case "$tool" in
  trivy)    url="https://github.com/aquasecurity/trivy/releases/download/v${version}/trivy_${version}_Linux-64bit.tar.gz" ;;
  cosign)   url="https://github.com/sigstore/cosign/releases/download/v${version}/cosign-linux-amd64" ;;
  gitleaks) url="https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_linux_x64.tar.gz" ;;
esac

tmp=${RUNNER_TEMP:-$(mktemp -d)}
asset="$tmp/${tool}-${version}.asset"
bindir="$tmp/${tool}-${version}-bin"

curl --fail --silent --show-error --location --retry 3 --proto '=https' -o "$asset" "$url"
echo "$sha256  $asset" | sha256sum --check --strict

mkdir -p "$bindir"
if [[ "$url" == *.tar.gz ]]; then
  tar -xzf "$asset" -C "$bindir" "$tool"
else
  mv "$asset" "$bindir/$tool"
fi
chmod 0755 "$bindir/$tool"

if [[ -n "${GITHUB_PATH:-}" ]]; then echo "$bindir" >> "$GITHUB_PATH"; fi
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "version=$version" >> "$GITHUB_OUTPUT"; fi
echo "$tool $version installed to $bindir (sha256 verified)"
