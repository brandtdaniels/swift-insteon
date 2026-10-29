#!/usr/bin/env bash
# Builds the insteon command for release and installs it into PREFIX/bin, with the bundle of
# the Insteon device catalog it names products from, which has to sit next to it. Installing
# then fetches the latest compatible catalog with 'insteon catalog update', which asks only the
# catalog's site; offline, the bundled copy is used.
#
# Usage: Scripts/install-insteon.sh [PREFIX]
#   PREFIX defaults to ~/.local, so the command goes in ~/.local/bin, which needs no sudo.
#   Make sure PREFIX/bin is on your PATH.
set -euo pipefail

prefix="${1:-$HOME/.local}"

# A relative PREFIX is relative to where the script was run, not to the package.
case "$prefix" in
  /*) ;;
  *) prefix="$PWD/$prefix" ;;
esac

destination="$prefix/bin"

# The nearest directory that's already there has to be writable, to make the rest in it.
existing="$destination"

while [ ! -e "$existing" ]; do
  existing="$(dirname "$existing")"
done

if [ ! -d "$existing" ] || [ ! -w "$existing" ]; then
  echo "install-insteon: $existing isn't a directory you can write to, so $destination can't be made there; give a PREFIX you can write to, such as ~/.local." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

swift build -c release --product insteon
build="$(swift build -c release --show-bin-path)"

mkdir -p "$destination"

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

# Best effort: the command works with the bundled catalog, so a failed update, such as when
# offline, doesn't fail the install. The update writes to the user's own cache, so it's
# skipped when installing as root, which would leave that cache owned by root.
if [ -z "$installed" ]; then
  :
elif [ "$(id -u)" -eq 0 ]; then
  echo "install-insteon: run 'insteon catalog update' as yourself, not as root, to fetch the latest Insteon device catalog." >&2
elif ! "$destination/insteon" catalog update; then
  echo "install-insteon: the latest Insteon device catalog couldn't be fetched; run 'insteon catalog update' later to fetch it." >&2
fi

case ":$PATH:" in
  *":$destination:"*) ;;
  *) echo "Add $destination to your PATH to run 'insteon' from anywhere." ;;
esac
