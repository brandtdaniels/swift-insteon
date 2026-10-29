#!/usr/bin/env bash
# Replaces InsteonDeviceCatalog's copy of the Insteon device catalog and its manifest with the
# published ones, after checking the catalog against the SHA-256 in the manifest.
#
# The package reads only catalogs with the MAJOR.MINOR of the copy it ships with, so a new
# MAJOR.MINOR is a change of format: check the package's decoding against it before shipping.
#
# Usage: Scripts/update-device-catalog.sh
set -euo pipefail

cd "$(dirname "$0")/.."

base="https://brandtdaniels.github.io/insteon-device-catalog/v0"
resources="Packages/InsteonDeviceCatalog/Sources/InsteonDeviceCatalog/Resources"
download="$(mktemp)"
manifest="$(mktemp)"
trap 'rm -f "$download" "$manifest"' EXIT

curl --fail --silent --show-error --output "$manifest" "$base/manifest.json"
read -r expected version < <(python3 -I -c 'import json, sys; manifest = json.load(open(sys.argv[1])); print(manifest["sha256"], manifest["version"])' "$manifest")

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

previous="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$resources/manifest.json" 2> /dev/null || true)"

chmod 644 "$download" "$manifest"
mv "$download" "$resources/catalog.json"
mv "$manifest" "$resources/manifest.json"
trap - EXIT
echo "Updated $resources/catalog.json and manifest.json to version $version"

if [ -n "$previous" ] && [ "${previous%.*}" != "${version%.*}" ]; then
  echo "The catalog's MAJOR.MINOR changed from ${previous%.*} to ${version%.*}: check that the package reads the new format." >&2
fi
