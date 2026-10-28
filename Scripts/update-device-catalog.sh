#!/usr/bin/env bash
# Replaces InsteonDeviceCatalog's copy of the Insteon device catalog with the published one,
# after checking it against the SHA-256 in the published manifest.
#
# Usage: Scripts/update-device-catalog.sh
set -euo pipefail

cd "$(dirname "$0")/.."

base="https://brandtdaniels.github.io/insteon-device-catalog/v1"
destination="Packages/InsteonDeviceCatalog/Sources/InsteonDeviceCatalog/Resources/catalog.json"
download="$(mktemp)"
trap 'rm -f "$download"' EXIT

manifest="$(curl --fail --silent --show-error "$base/manifest.json")"
expected="$(printf '%s' "$manifest" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["sha256"])')"

curl --fail --silent --show-error --output "$download" "$base/catalog.json"

if command -v sha256sum > /dev/null; then
  actual="$(sha256sum "$download" | cut -d ' ' -f 1)"
else
  actual="$(shasum -a 256 "$download" | cut -d ' ' -f 1)"
fi

if [ "$actual" != "$expected" ]; then
  echo "catalog.json doesn't match the manifest's SHA-256" >&2
  exit 1
fi

chmod 644 "$download"
mv "$download" "$destination"
trap - EXIT
echo "Updated $destination"
