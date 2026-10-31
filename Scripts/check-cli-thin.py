#!/usr/bin/env python3
"""Checks that the `insteon` command stays a thin layer over the libraries.

Usage: python3 Scripts/check-cli-thin.py [--root DIR] [--allowlist FILE] [--update]

The command parses arguments, prompts and prints; what a device is and how to control it comes
from the Insteon device catalog through the libraries. So its sources mustn't compare a
device's category, subcategory, firmware version, engine or group kind, and mustn't hold
protocol bytes or command numbers: hexadecimal literals, or the protocol's command
enumerations.

It reads the Swift files under the root, `Packages/InsteonCLI/Sources/insteon` by default,
leaving out comments and string literals, and prints each line that breaks a rule. A line
that's in the allow-list, `Scripts/check-cli-thin-allowlist.txt` by default, is known and
waits to move into the libraries; any other is new, and so is a failure. An allow-list entry
that no longer matches anything is a failure too, so the list only shrinks: remove the entry.
`--update` writes the allow-list from what the sources hold, for a change that moves code
into the libraries. It exits with status 1 on a failure.
"""

import argparse
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_SOURCES = ROOT / "Packages" / "InsteonCLI" / "Sources" / "insteon"

DEFAULT_ALLOWLIST = ROOT / "Scripts" / "check-cli-thin-allowlist.txt"

# The raw passthroughs, `insteon device ADDRESS send` and `insteon modem send`, send bytes as
# the person typed them, so they hold protocol bytes by design. Only the rules about bytes and
# command numbers are waived for them; they still mustn't compare identities.
PASSTHROUGH_FILES = {
    "ExploreCommands.swift",
}

# A comparison: ==, !=, <=, >=, ~=, or < or > with spaces around them, so `->` and generics
# aren't comparisons.
COMPARISON = r"(?:==|!=|<=|>=|~=|\s<\s|\s>\s)"

# Each rule: its name, a regular expression for code that breaks it, whether the raw
# passthroughs are waived from it, and what to do instead.
RULES = [
    (
        "category",
        re.compile(
            r"\w*[cC]ategory\??\s*" + COMPARISON
            + r"|" + COMPARISON + r"\s*[\w.]*[cC]ategory\b"
            + r"|\bcase\s+\.(?:dimmableLightingControl|switchedLightingControl)\b"
            + r"|\bswitch\s+[\w.?]*[cC]ategory\b"
        ),
        False,
        "ask the libraries what the device can do, such as a Device's capabilities",
    ),
    (
        "firmware",
        re.compile(
            r"\w*[fF]irmware\w*\??\s*(?:\?\?\s*[\w.]+\)?\s*)?" + COMPARISON
            + r"|" + COMPARISON + r"\s*[\w.]*[fF]irmware\w*"
        ),
        False,
        "let the Insteon device catalog choose by firmware version",
    ),
    (
        "group-kind",
        re.compile(
            r"\bkind\??\s*(?:==|!=)"
            + r"|(?:==|!=)\s*\.(?:dimmer|relay|fan|sensor|button)\b"
            + r"|\bcase\s+\.(?:dimmer|relay|fan|sensor|button)\b"
            + r"|\bmainGroupType\b|\bGroupType\.Kind\b"
        ),
        False,
        "ask the libraries what the group can do, such as DeviceGroup.canDim",
    ),
    (
        "engine",
        re.compile(r"(?:==|!=)\s*\.(?:i1|i2|i2cs|i3)\b|\bcase\s+\.(?:i1|i2|i2cs|i3)\b"),
        False,
        "let the libraries choose the form a message takes for the device's engine",
    ),
    (
        "hex-literal",
        re.compile(r"\b0[xX][0-9A-Fa-f]+\b"),
        True,
        "name the command or value in a library, or take it from the catalog",
    ),
    (
        "protocol-command",
        re.compile(r"\b(?:StandardDirectCommand|ExtendedDirectCommand)\b"),
        True,
        "call a library operation, such as Device.turnOn(level:group:)",
    ),
]


def code_lines(text):
    """Yields each line number and its code, without comments or string literals.

    A string literal becomes `""`, followed by the code of its interpolations, so a comparison
    can't hide in one. Block comments and `//` comments are removed.
    """

    in_block_comment = False
    in_multiline_string = False

    for number, line in enumerate(text.split("\n"), start=1):
        code = []
        index = 0

        while index < len(line):
            if in_block_comment:
                end = line.find("*/", index)

                if end < 0:
                    index = len(line)
                else:
                    in_block_comment = False
                    index = end + 2

                continue

            if in_multiline_string:
                index, interpolations, closed = scan_string(line, index, '"""')
                code.append(interpolations)

                if closed:
                    in_multiline_string = False
                    code.append('""')

                continue

            if line.startswith("//", index):
                break

            if line.startswith("/*", index):
                in_block_comment = True
                index += 2
                continue

            if line.startswith('"""', index):
                in_multiline_string = True
                index += 3
                continue

            if line[index] == '"':
                index, interpolations, _ = scan_string(line, index + 1, '"')
                code.append('""' + interpolations)
                continue

            code.append(line[index])
            index += 1

        yield number, "".join(code)


def scan_string(line, index, closing):
    """Reads a string literal's contents from `index` to its closing quotes, skipping escapes.

    Returns the index after the closing quotes, or the line's end; the code of the
    interpolations, each followed by a space; and whether the string closed on the line.
    """

    interpolations = []

    while index < len(line):
        if line.startswith("\\(", index):
            end, inner = interpolation(line, index + 2)
            interpolations.append(inner + " ")
            index = end
            continue

        if line[index] == "\\":
            index += 2
            continue

        if line.startswith(closing, index):
            return index + len(closing), "".join(interpolations), True

        index += 1

    return index, "".join(interpolations), False


def interpolation(line, index):
    """Reads an interpolation's code from `index`, after its `\\(`, to its closing parenthesis.

    Returns the index after the parenthesis and the code, with its own string literals as
    `""` followed by their interpolations.
    """

    depth = 0
    code = []

    while index < len(line):
        character = line[index]

        if character == '"':
            index, inner, _ = scan_string(line, index + 1, '"')
            code.append('""' + inner)
            continue

        if character == "(":
            depth += 1
        elif character == ")":
            if depth == 0:
                return index + 1, "".join(code)

            depth -= 1

        code.append(character)
        index += 1

    return index, "".join(code)


def normalized(code):
    """A line's code with its whitespace collapsed, as the allow-list holds it."""

    return " ".join(code.split())


def violations(sources):
    """Each line that breaks a rule, as (path, rule, code, line number), in file order."""

    found = []

    for path in sorted(sources.rglob("*.swift")):
        relative = path.relative_to(sources).as_posix()
        is_passthrough = path.name in PASSTHROUGH_FILES

        for number, code in code_lines(path.read_text(encoding="utf-8")):
            for name, pattern, waived_for_passthrough, _ in RULES:
                if is_passthrough and waived_for_passthrough:
                    continue

                if pattern.search(code):
                    found.append((relative, name, normalized(code), number))

    return found


def read_allowlist(path):
    """The allow-list's entries, as (path, rule, code), each as many times as it's listed."""

    entries = collections.Counter()

    if not path.exists():
        return entries

    for line in path.read_text(encoding="utf-8").split("\n"):
        if not line.strip() or line.startswith("#"):
            continue

        parts = line.split("\t", 2)

        if len(parts) != 3:
            sys.exit(f"{path}: not an entry, which is a path, a rule and code separated by tabs: {line}")

        entries[tuple(parts)] += 1

    return entries


ALLOWLIST_HEADER = """\
# Lines of the `insteon` command that Scripts/check-cli-thin.py knows break its rules, waiting
# to move into the libraries. Each entry is a path under Packages/InsteonCLI/Sources/insteon,
# the rule, and the line's code without comments or strings, separated by tabs. Entries only
# go: a change that moves code into the libraries removes them, with --update.
"""


def write_allowlist(path, found):
    """Writes the allow-list from the lines that break a rule."""

    lines = [f"{relative}\t{name}\t{code}" for relative, name, code, _ in found]

    path.write_text(ALLOWLIST_HEADER + "\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def main(arguments=None):
    parser = argparse.ArgumentParser(description="Checks that the insteon command stays a thin layer.")
    parser.add_argument("--root", type=pathlib.Path, default=DEFAULT_SOURCES, help="the sources to check")
    parser.add_argument("--allowlist", type=pathlib.Path, default=DEFAULT_ALLOWLIST, help="the known lines")
    parser.add_argument("--update", action="store_true", help="write the allow-list from the sources")
    options = parser.parse_args(arguments)

    found = violations(options.root)

    if options.update:
        write_allowlist(options.allowlist, found)
        print(f"Wrote {len(found)} known lines to {options.allowlist}.")
        return 0

    allowed = read_allowlist(options.allowlist)
    remaining = collections.Counter(allowed)
    advice = {name: instead for name, _, _, instead in RULES}
    failed = False

    for relative, name, code, number in found:
        key = (relative, name, code)

        if remaining[key] > 0:
            remaining[key] -= 1
            continue

        failed = True
        print(f"{relative}:{number}: {name}: {code}")
        print(f"  The insteon command doesn't decide what a device does: {advice[name]}.")

    for (relative, name, code), count in sorted(remaining.items()):
        if count > 0:
            failed = True
            print(f"{options.allowlist.name}: no longer found, so remove it: {relative}\t{name}\t{code}")

    if failed:
        return 1

    known = sum(allowed.values())
    print(f"The insteon command stays thin: no new lines break the rules ({known} known, in {options.allowlist.name}).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
