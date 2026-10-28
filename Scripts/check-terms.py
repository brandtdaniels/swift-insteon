#!/usr/bin/env python3
"""Checks the docs and comments for the terms CONVENTIONS.md rules out.

Usage: python3 Scripts/check-terms.py

It reads Swift comments and Markdown outside code spans and code blocks, and prints each
line that uses a ruled-out form with the form to use instead. It exits with status 1 if it
finds any. CONVENTIONS.md, which names the ruled-out forms, and the bundled catalog, whose text
refreshing it from the catalog fixes, are left alone.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# A ruled-out form, as a regular expression, and what to write instead.
RULES = [
    (r"\bINSTEON\b", "Insteon"),
    (r"(?<![.\w])[iI]2cs\b|\bI2CS\b", "i2CS"),
    (r"\b[Aa]cknowledgement", "acknowledgment"),
    (r"\b[Pp]ower line", "powerline"),
    (r"\bon level\b", "on-level"),
    (r"\b(2242|2245) Hub\b", "Hub 2242, Hub 2245"),
    (r"\bHub Pro \(2243", "Hub Pro 2243"),
    # Models run from 2200 up; a year in parentheses, as in a citation, is fine.
    (r"\b[A-Z][\w-]*(?: [A-Z][\w-]*)* \(2[2-9]\d\d[A-Z0-9-]*(?:,? (?:or |and )?2[2-9]\d\d[A-Z0-9-]*)*\)", "the name, then the model, without parentheses"),
    (r"\bAll-Link|\ball-link", "ALL-Link"),
    (r"(?<!ALL-)(?<!All-)\blink database", "ALL-Link database"),
    (r"\bclean-up", "cleanup"),
    (r"\b[Ss]et button\b", "SET button"),
]


def prose(path):
    """Yields each line number and the prose on it, with code spans removed."""

    in_block = False

    for number, line in enumerate(path.read_text().split("\n"), start=1):
        if path.suffix == ".md":
            if line.lstrip().startswith("```"):
                in_block = not in_block
                continue

            text = "" if in_block else line
        else:
            comment = re.search(r"//.*$", line)
            text = comment.group(0) if comment and '"' not in line[:comment.start()] else ""

        yield number, re.sub(r"`[^`]*`", "", text)


def main():
    problems = []
    paths = [path for path in ROOT.rglob("*") if path.suffix in {".swift", ".md"}]

    for path in sorted(paths):
        if {".build", ".git"} & set(path.parts) or path.name == "CONVENTIONS.md":
            continue

        for number, text in prose(path):
            for pattern, replacement in RULES:
                if found := re.search(pattern, text):
                    problems.append(f"{path.relative_to(ROOT)}:{number}: {found.group(0)!r}: use {replacement}")

    print("\n".join(problems) or "No ruled-out terms.")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
