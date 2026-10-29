#!/usr/bin/env bash
# Builds the insteon command for release and installs it into PREFIX/bin, with the bundle of
# the Insteon device catalog it names products from, which has to sit next to it.
#
# Usage: Scripts/install-insteon.sh [PREFIX]
#   PREFIX defaults to ~/.local, so the command goes in ~/.local/bin, which needs no sudo.
#   Make sure PREFIX/bin is on your PATH.
set -euo pipefail

cd "$(dirname "$0")/.."

prefix="${1:-$HOME/.local}"
destination="$prefix/bin"

swift build -c release --product insteon
build="$(swift build -c release --show-bin-path)"

mkdir -p "$destination"

if [ ! -w "$destination" ]; then
  echo "install-insteon: $destination isn't writable; give a PREFIX you can write to, such as ~/.local." >&2
  exit 1
fi

install -m 755 "$build/insteon" "$destination/insteon"

# The Swift Package Manager names the bundle .bundle on macOS and .resources on Linux.
installed=""

for bundle in swift-insteon_InsteonDeviceCatalog.bundle swift-insteon_InsteonDeviceCatalog.resources; do
  if [ -d "$build/$bundle" ]; then
    rm -rf "${destination:?}/$bundle"
    cp -R "$build/$bundle" "$destination/$bundle"
    installed="$bundle"
  fi
done

if [ -z "$installed" ]; then
  echo "install-insteon: the Insteon device catalog's bundle wasn't found in $build; the command will run without product names." >&2
fi

echo "Installed $destination/insteon${installed:+ and $destination/$installed}"

case ":$PATH:" in
  *":$destination:"*) ;;
  *) echo "Add $destination to your PATH to run 'insteon' from anywhere." ;;
esac
