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

# What 'insteon catalog update' exits with: 0 when it updated the catalog or kept the copy for
# another reason, 3 when the published catalog was refused for relaxing safeguards, 4 when the
# copy in use is already the published one, and anything else when it couldn't fetch or check it.
catalog_refused=3
catalog_current=4

# Best effort: the command works with the bundled catalog, so a refused or failed update, such as
# when offline, doesn't fail the install. Takes the installed command.
update_catalog() {
  local command="$1" status=0

  "$command" catalog update || status=$?

  case "$status" in
    0) ;;
    "$catalog_current")
      echo "install-insteon: the Insteon device catalog is already current."
      ;;
    "$catalog_refused")
      echo "install-insteon: the published Insteon device catalog relaxes safeguards the bundled one keeps, so the bundled catalog stays; run 'insteon catalog update --explain' to see why." >&2
      ;;
    *)
      echo "install-insteon: the latest Insteon device catalog couldn't be fetched; run 'insteon catalog update' later to fetch it." >&2
      ;;
  esac

  return 0
}

main() {
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

  # The update writes to the user's own cache, so it's skipped when installing as root, which
  # would leave that cache owned by root.
  if [ -z "$installed" ]; then
    :
  elif [ "$(id -u)" -eq 0 ]; then
    echo "install-insteon: run 'insteon catalog update' as yourself, not as root, to fetch the latest Insteon device catalog." >&2
  else
    update_catalog "$destination/insteon"
  fi

  case ":$PATH:" in
    *":$destination:"*) ;;
    *) echo "Add $destination to your PATH to run 'insteon' from anywhere." ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
