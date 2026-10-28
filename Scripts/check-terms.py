#!/usr/bin/env python3
"""Checks the docs and comments for the terms CONVENTIONS.md rules out.

Usage: python3 Scripts/check-terms.py

It reads Swift comments and Markdown, leaving out code spans, code blocks and string literals,
and prints each line that uses a ruled-out form with the form to use instead. It exits with
status 1 if it finds any. CONVENTIONS.md, which names the ruled-out forms, isn't read, and nor
are other file types, such as the bundled catalog.json, whose text the catalog fixes.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# A ruled-out form, as a regular expression, and what to write instead.
RULES = [
    (r"\bINSTEON\b", "Insteon"),
    (r"(?<![.\w/])[iI]2cs\b|\bI2CS\b", "i2CS"),
    (r"\b[Aa]cknowledgement", "acknowledgment"),
    (r"\b[Pp]ower [Ll]ine", "powerline"),
    (r"\b[Oo]n levels?\b", "on-level"),
    (r"\b(2242|2245) Hub\b", "Hub 2242, Hub 2245"),
    # A model in parentheses after a name. Models run from 2200 to 2999; a year in parentheses,
    # as in a citation, is fine.
    (r"\b[A-Za-z][\w-]* \(2[2-9]\d\d(?!\d)[A-Z0-9-]*[^)]*\)", "the name, then the model, without parentheses"),
    (r"\bAll-Link|\ball-link", "ALL-Link"),
    (r"(?<!ALL-)\b[Ll]ink database", "ALL-Link database"),
    (r"\bclean-up", "cleanup"),
    (r"\b[Ss]et button\b", "SET button"),
    (r"(?<!Insteon )(?<!Modem )(?<!Hub )\b[Dd]eveloper'?s? [Gg]uides?\b|\b[Tt]he guide\b", "the document's title, such as Insteon Developer's Guide"),
    (r"\bPRDs?\b|[Pp]roduct requirements|[Ww]orkbook|[Cc]ommand sheets?|[Tt]est log|SKU list|for Hub app|Insteon's Hub app|InsteonDevices\.db", "a public document's title, or no citation"),
]

FENCE = re.compile(r"^\s*(?:///?\s*)?(```|~~~)")


def without_code(text):
    """The text with its code spans, of any number of backticks, removed."""

    return re.sub(r"(`+).+?\1", "", text)


def prose(path):
    """Yields each line number and the prose on it."""

    in_fence = False
    in_string = False

    for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue

        if path.suffix == ".md":
            # Indented code blocks start with four spaces outside a list.
            if in_fence or (line.startswith("    ") and not line.lstrip().startswith(("-", "*", "1", "2", "3", "4", "5", "6", "7", "8", "9"))):
                continue

            yield number, without_code(line)
            continue

        if in_string:
            in_string = '"""' not in line
            continue

        code = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)

        if code.count('"""') % 2 == 1:
            in_string = True
            continue

        comment = re.search(r"//.*$", code)

        if comment and not in_fence:
            yield number, without_code(comment.group(0))


def main():
    problems = []

    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)

        if path.suffix not in {".swift", ".md"} or {".build", ".git"} & set(relative.parts) or path.name == "CONVENTIONS.md":
            continue

        for number, text in prose(path):
            for pattern, replacement in RULES:
                if found := re.search(pattern, text):
                    problems.append(f"{relative}:{number}: {found.group(0)!r}: use {replacement}")

    print("\n".join(problems) or "No ruled-out terms.")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
