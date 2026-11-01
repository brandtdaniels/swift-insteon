#!/usr/bin/env python3
"""Checks the sources for credentials written into a string by interpolation.

Usage: python3 Scripts/check-credentials.py [--root DIR] [--allowlist FILE] [--update]

A Hub's username and password, and any token or Authorization header, go only into the
request that needs them. Written into a string, such as `"\\(password)"` in a message, a log
line or an error's description, they can end up on a screen or in a file. So no string in the
sources interpolates a value whose name says it's a credential: a name with `password`,
`passwd`, `token`, `secret`, `credential`, `authorization`, `apiKey` or `bearer` in it, in any
case, such as `hub.password` or `authorizationHeader`.

It reads the Swift files under `Packages/*/Sources`, the command included, leaving out
comments, and prints each line whose string interpolates such a name by its path under
`Packages`. A line in the allow-list, `Scripts/check-credentials-allowlist.txt` by default, is
known and has a reason, such as a name that holds no credential; any other is a failure. An
entry that no longer matches anything is a failure too, so the list only shrinks: remove the
entry. `--update` writes the allow-list from what the sources hold, keeping the reasons of the
entries that remain; give each new one a reason. It exits with status 1 on a failure.
"""

import argparse
import collections
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_ROOT = ROOT / "Packages"

DEFAULT_ALLOWLIST = ROOT / "Scripts" / "check-credentials-allowlist.txt"

# The comment and string reader check-cli-thin.py uses.
_spec = importlib.util.spec_from_file_location("check_cli_thin", ROOT / "Scripts" / "check-cli-thin.py")
_thin = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_thin)

# A word that says a name holds a credential, matched in any case anywhere in an identifier.
CREDENTIAL = re.compile(r"password|passwd|token|secret|credential|authorization|apikey|api_key|bearer", re.IGNORECASE)

IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def interpolation_lines(text):
    """Yields each line number and the code of the interpolations in its strings.

    It reads the text as check-cli-thin.py's `code_lines` does, so comments are left out, and
    keeps only the code `scan_string` returns for each string's interpolations.
    """

    found = []
    scan_string = _thin.scan_string

    def recording(line, index, closing, hashes=0):
        result = scan_string(line, index, closing, hashes)
        found.append(result[1])
        return result

    _thin.scan_string = recording

    try:
        for number, _ in _thin.code_lines(text):
            yield number, "".join(found)
            found.clear()
    finally:
        _thin.scan_string = scan_string


def credential_names(code):
    """The identifiers in some code whose names say they hold a credential."""

    return [name for name in IDENTIFIER.findall(code) if CREDENTIAL.search(name)]


def violations(root):
    """Each line whose strings interpolate a credential's name, as (path, names, line
    number), in file order. The names are joined with commas, as the allow-list holds them."""

    found = []

    for path in sorted(root.glob("*/Sources/**/*.swift")):
        relative = path.relative_to(root)

        for number, code in interpolation_lines(path.read_text(encoding="utf-8")):
            names = credential_names(code)

            if names:
                found.append((relative.as_posix(), ",".join(sorted(set(names))), number))

    return found


ALLOWLIST_HEADER = """\
# Lines whose strings Scripts/check-credentials.py knows interpolate a name that looks like a
# credential's, each with a reason. Each entry is a path under Packages, the names, separated
# by commas, and why the line is safe, separated by tabs. Entries only go: CI fails a pull
# request that adds one.
"""


def read_allowlist(path):
    """The allow-list's entries, as (path, names), each as many times as it's listed, and the
    reasons by entry."""

    entries = collections.Counter()
    reasons = {}

    if not path.exists():
        return entries, reasons

    for line in path.read_text(encoding="utf-8").split("\n"):
        if not line.strip() or line.startswith("#"):
            continue

        parts = line.split("\t")

        if len(parts) != 3 or not parts[2].strip():
            sys.exit(f"{path}: not an entry, which is a path, names and a reason separated by tabs: {line}")

        key = tuple(parts[:2])
        entries[key] += 1
        reasons[key] = parts[2]

    return entries, reasons


def write_allowlist(path, found, reasons):
    """Writes the allow-list from the lines found, keeping known reasons."""

    lines = [f"{relative}\t{names}\t{reasons.get((relative, names), '')}" for relative, names, _ in found]

    path.write_text(ALLOWLIST_HEADER + "\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def main(arguments=None):
    parser = argparse.ArgumentParser(description="Checks the sources for credentials in strings.")
    parser.add_argument("--root", type=pathlib.Path, default=DEFAULT_ROOT, help="the packages, each with Sources")
    parser.add_argument("--allowlist", type=pathlib.Path, default=DEFAULT_ALLOWLIST, help="the known lines")
    parser.add_argument("--update", action="store_true", help="write the allow-list from the sources")
    options = parser.parse_args(arguments)

    found = violations(options.root)

    if options.update:
        _, reasons = read_allowlist(options.allowlist)
        write_allowlist(options.allowlist, found, reasons)
        print(f"Wrote {len(found)} known lines to {options.allowlist}. Give each new one a reason.")
        return 0

    allowed, _ = read_allowlist(options.allowlist)
    remaining = collections.Counter(allowed)
    failed = False

    for relative, names, number in found:
        key = (relative, names)

        if remaining[key] > 0:
            remaining[key] -= 1
            continue

        failed = True
        print(f"{relative}:{number}: interpolates {names}")
        print("  Instead, leave the credential out of the string, such as by naming what it's for.")

    for (relative, names), count in sorted(remaining.items()):
        if count > 0:
            failed = True
            print(f"{options.allowlist.name}: no longer found, so remove it: {relative}\t{names}")

    if failed:
        return 1

    known = sum(allowed.values())
    print(f"No credentials interpolated into strings ({known} known, in {options.allowlist.name}).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
