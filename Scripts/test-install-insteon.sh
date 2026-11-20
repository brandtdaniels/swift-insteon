#!/usr/bin/env bash
# Tests how Scripts/install-insteon.sh reports 'insteon catalog update', with a fake command that
# exits with the status it's given. It sources the installer, which runs nothing when sourced.
#
# Usage: Scripts/test-install-insteon.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# shellcheck disable=SC1091
source "$here/install-insteon.sh"

fake="$scratch/insteon"
cat > "$fake" <<'FAKE'
#!/usr/bin/env bash
echo "fake insteon: $*"
exit "${FAKE_STATUS:?}"
FAKE
chmod 755 "$fake"

failures=0

# Runs the installer's update step with the fake command exiting with $1, and checks the
# step's own status, standard output and standard error.
expect() {
  local name="$1" status="$2" want_out="$3" want_err="$4" out err code=0

  FAKE_STATUS="$status" update_catalog "$fake" > "$scratch/out" 2> "$scratch/err" || code=$?
  out="$(cat "$scratch/out")"
  err="$(cat "$scratch/err")"

  if [ "$code" -ne 0 ] || [ "$out" != "$want_out" ] || [ "$err" != "$want_err" ]; then
    echo "FAIL $name: status $code" >&2
    echo "  stdout: $out" >&2
    echo "  stderr: $err" >&2
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

updated="fake insteon: catalog update"

expect "an updated catalog says nothing more" 0 "$updated" ""

expect "a current catalog says so" 4 \
  "$updated
install-insteon: the Insteon device catalog is already current." ""

expect "a refused catalog says why and how to see more" 3 "$updated" \
  "install-insteon: the published Insteon device catalog relaxes safeguards the bundled one keeps, so the bundled catalog stays; run 'insteon catalog update --explain' to see why."

expect "an unreachable catalog keeps the existing wording" 1 "$updated" \
  "install-insteon: the latest Insteon device catalog couldn't be fetched; run 'insteon catalog update' later to fetch it."

expect "any other status is a failed fetch" 64 "$updated" \
  "install-insteon: the latest Insteon device catalog couldn't be fetched; run 'insteon catalog update' later to fetch it."

if [ "$failures" -ne 0 ]; then
  echo "$failures failed" >&2
  exit 1
fi
