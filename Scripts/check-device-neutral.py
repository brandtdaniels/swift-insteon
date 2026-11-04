#!/usr/bin/env python3
"""Checks that InsteonCore, the insteon command and the in-memory modem know no device.

Usage: python3 Scripts/check-device-neutral.py [--root DIR] [--catalog FILE] [--allowlist FILE] [--update]

What a device is and does comes from the Insteon device catalog, so the libraries a front end
uses, their command and their tests, sources and docs alike, don't name a real product or one
of its operating flags: a test builds an invented catalog with invented names instead. The
words ruled out come from the bundled catalog as the check runs, so they follow it:

- each device's name, aliases and model, apart from a modem's or a Hub's, which the libraries
  talk through rather than control, matched with the case the catalog gives, since they're
  proper names and the same words in lowercase, such as "a dimmer switch", are plain English;
- each command set's id, and each operating flag's name and label and extended setting's name
  in every command set, matched in any case, so `ioLinc`, `IOLinc` and `iolinc` are all found;
- the words in `EXPLICIT`, product names the catalog doesn't spell that way, in any case.

A word in `GENERIC` is left out, in any case, even when the catalog uses it, since it's also a
word of the protocol, such as heartbeat or on-level's `onLevel`, or of plain English. A word
matches only whole: not as part of a longer word or name, so `pulse` doesn't match `pulseBoth`.

It reads every file under `Packages/InsteonCore`, `Packages/InsteonCLI` and
`Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport` in the root, and prints each
word it finds, by the file's path from the root and the line it's first on. A file and word in
the allow-list, `Scripts/check-device-neutral-allowlist.txt` by default, are known, and wait to
be made neutral; any other is a failure.

To allow an exception, add a line to the allow-list: the file's path from the root, the word,
and the reason, separated by tabs. CI fails a pull request that adds one, so an exception is a
deliberate change a reviewer sees; prefer an invented name. An entry that no longer matches
anything is a failure too, so the list only shrinks: remove the entry. `--update` writes the
allow-list from what the files hold, keeping the reasons of the entries that remain; give each
new one a reason. It exits with status 1 on a failure.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_CATALOG = ROOT / "Packages" / "InsteonDeviceCatalog" / "Sources" / "InsteonDeviceCatalog" / "Resources" / "catalog.json"

DEFAULT_ALLOWLIST = ROOT / "Scripts" / "check-device-neutral-allowlist.txt"

# The directories read, from the root.
CHECKED = [
    pathlib.Path("Packages") / "InsteonCore",
    pathlib.Path("Packages") / "InsteonCLI",
    pathlib.Path("Packages") / "InsteonTestSupport" / "Sources" / "InsteonLinkingTestSupport",
]

# Products the catalog spells otherwise, ruled out too, in any case.
EXPLICIT = {"I/O Linc", "IOLinc", "IO Linc"}

# Words the catalog uses that are also the protocol's or plain English, so they're allowed, in
# any case.
GENERIC = {
    # A message a battery-powered device sends, as the Insteon Developer's Guide names it, and
    # its battery level.
    "heartbeat",
    "batterylevel",
    # The Get Operating Flags and Set Operating Flags commands' byte.
    "operatingflags",
    # A responder record's on-level and ramp rate, which every dimmer's link data names.
    "onlevel",
    "ramprate",
    # Plain English.
    "grouped",
    "configuration",
    "beeper",
}

# A device the libraries talk through, rather than control, has one of these capabilities.
TRANSPORT_CAPABILITIES = {"modem", "hub"}


def forbidden_words(catalog_path):
    """The words ruled out, from the catalog at a path, with `EXPLICIT` and without `GENERIC`,
    each with whether it matches in any case."""

    catalog = json.loads(pathlib.Path(catalog_path).read_text(encoding="utf-8"))
    words = {word: True for word in EXPLICIT}

    def add(word, any_case):
        if word and word.casefold() not in GENERIC:
            words[word] = words.get(word, False) or any_case

    for device in catalog.get("devices", []):
        kinds = {capability.get("kind") for capability in device.get("capabilities", [])}

        if kinds & TRANSPORT_CAPABILITIES:
            continue

        for word in [device.get("name"), device.get("model"), *(device.get("aliases") or [])]:
            add(word, False)

    for command_set in catalog.get("commandSets", []):
        add(command_set.get("id"), True)

        for flag in command_set.get("operatingFlags", []):
            add(flag.get("name"), True)
            add(flag.get("label"), True)

        for value in (command_set.get("extendedSettings") or {}).get("values", []):
            add(value.get("name"), True)

    return words


def pattern(word, any_case=False):
    """A pattern that finds a word whole: not inside a longer word, name or number."""

    return re.compile(r"(?<![A-Za-z0-9_])" + re.escape(word) + r"(?![A-Za-z0-9_])", re.IGNORECASE if any_case else 0)


def violations(root, words):
    """Each file and word found, as (path, word, line number of its first use), in path and
    then word order."""

    patterns = {word: pattern(word, any_case) for word, any_case in words.items()}
    found = []

    for directory in CHECKED:
        base = root / directory

        if not base.exists():
            continue

        for path in sorted(base.rglob("*")):
            if not path.is_file():
                continue

            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue

            relative = path.relative_to(root).as_posix()

            for word in sorted(words):
                match = patterns[word].search(text)

                if match:
                    found.append((relative, word, text.count("\n", 0, match.start()) + 1))

    return sorted(found)


ALLOWLIST_HEADER = """\
# Files that Scripts/check-device-neutral.py knows name a real product or operating flag, each
# with a reason. Each entry is a path from the repository's root, the word, and why it stays,
# separated by tabs. Entries only go: CI fails a pull request that adds one.
"""


def read_allowlist(path):
    """The allow-list's entries, as a set of (path, word), and the reasons by entry."""

    entries = set()
    reasons = {}

    if not path.exists():
        return entries, reasons

    for line in path.read_text(encoding="utf-8").split("\n"):
        if not line.strip() or line.startswith("#"):
            continue

        parts = line.split("\t")

        if len(parts) != 3 or not parts[2].strip():
            sys.exit(f"{path}: not an entry, which is a path, a word and a reason separated by tabs: {line}")

        key = (parts[0], parts[1])
        entries.add(key)
        reasons[key] = parts[2]

    return entries, reasons


def write_allowlist(path, found, reasons):
    """Writes the allow-list from what was found, keeping known reasons."""

    lines = [f"{relative}\t{word}\t{reasons.get((relative, word), '')}" for relative, word, _ in found]

    path.write_text(ALLOWLIST_HEADER + "\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def main(arguments=None):
    parser = argparse.ArgumentParser(description="Checks that the core, the command and the in-memory modem know no device.")
    parser.add_argument("--root", type=pathlib.Path, default=ROOT, help="the repository, with Packages")
    parser.add_argument("--catalog", type=pathlib.Path, default=DEFAULT_CATALOG, help="the catalog the words come from")
    parser.add_argument("--allowlist", type=pathlib.Path, default=DEFAULT_ALLOWLIST, help="the known files and words")
    parser.add_argument("--update", action="store_true", help="write the allow-list from the files")
    options = parser.parse_args(arguments)

    found = violations(options.root, forbidden_words(options.catalog))

    if options.update:
        _, reasons = read_allowlist(options.allowlist)
        write_allowlist(options.allowlist, found, reasons)
        print(f"Wrote {len(found)} known files and words to {options.allowlist}. Give each new one a reason.")
        return 0

    allowed, _ = read_allowlist(options.allowlist)
    failed = False
    seen = set()

    for relative, word, number in found:
        key = (relative, word)
        seen.add(key)

        if key in allowed:
            continue

        failed = True
        print(f"{relative}:{number}: names {word}, a real product or operating flag")
        print("  Instead, take it from the catalog, or use an invented name in a test's own catalog.")

    for relative, word in sorted(allowed - seen):
        failed = True
        print(f"{options.allowlist.name}: no longer found, so remove it: {relative}\t{word}")

    if failed:
        return 1

    print(f"No real product or operating flag named ({len(allowed)} known, in {options.allowlist.name}).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
