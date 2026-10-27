#!/usr/bin/env bash
# Builds the DocC documentation for every library in the package and fails on any warning.
#
# Usage: Scripts/build-docs.sh
# Output: .build/docs/<Module>.doccarchive
set -euo pipefail

cd "$(dirname "$0")/.."

graphs="$PWD/.build/symbol-graphs"
output="$PWD/.build/docs"
rm -rf "$graphs" "$output"
mkdir -p "$graphs" "$output"

swift build \
  -Xswiftc -emit-symbol-graph \
  -Xswiftc -emit-symbol-graph-dir -Xswiftc "$graphs"

if command -v docc > /dev/null; then
  docc=(docc)
else
  docc=(xcrun docc)
fi

for catalog in Packages/*/Sources/*/*.docc; do
  module="$(basename "$catalog" .docc)"
  module_graphs="$graphs/$module"
  mkdir -p "$module_graphs"

  # Each catalog gets only its own module's symbol graphs.
  find "$graphs" -maxdepth 1 \( -name "$module.symbols.json" -o -name "$module@*.symbols.json" \) \
    -exec cp {} "$module_graphs/" \;

  echo "Building documentation for $module"
  "${docc[@]}" convert "$catalog" \
    --additional-symbol-graph-dir "$module_graphs" \
    --fallback-display-name "$module" \
    --fallback-bundle-identifier "com.brandtdaniels.$module" \
    --output-path "$output/$module.doccarchive" \
    --warnings-as-errors
done
