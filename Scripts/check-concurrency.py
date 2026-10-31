#!/usr/bin/env python3
"""Checks the libraries for concurrency that escapes structure or a test's clock.

Usage: python3 Scripts/check-concurrency.py [--root DIR] [--allowlist FILE] [--update]

The libraries keep their work structured and their time on a clock the caller can replace,
so a canceled call stops what it started and a test's TestClock sets every timeout. So their
sources mustn't use:

- an unstructured task, `Task { ... }`, `Task(priority:) { ... }` or `Task.detached`, which
  outlives the call that starts it unless it's awaited;
- `@unchecked Sendable`, which turns off the compiler's check of a type's shared state;
- `Task.sleep`, which sleeps on the real clock;
- `ContinuousClock()` or `SuspendingClock()`, except as a parameter's default value, such as
  `clock: any Clock<Duration> = ContinuousClock()`, which a caller can replace.

It reads the Swift files under `Packages/*/Sources`, except the `insteon` command and the test
doubles in `InsteonTestSupport`, leaving out comments and string literals, and prints each line
that breaks a rule by its path under `Packages`. A line in the allow-list,
`Scripts/check-concurrency-allowlist.txt` by default, is known and has a reason; any other is
a failure. An entry that no longer matches anything is a failure too, so the list only
shrinks: remove the entry. `--update` writes the allow-list from what the sources hold,
keeping the reasons of the entries that remain; give each new one a reason. It exits with
status 1 on a failure.
"""

import argparse
import collections
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_ROOT = ROOT / "Packages"

DEFAULT_ALLOWLIST = ROOT / "Scripts" / "check-concurrency-allowlist.txt"

# Sources that aren't library code: the command, and the test doubles.
EXCLUDED = [
    ("InsteonCLI", "Sources", "insteon"),
    ("InsteonTestSupport",),
]

# The comment and string stripper check-cli-thin.py uses.
_spec = importlib.util.spec_from_file_location("check_cli_thin", ROOT / "Scripts" / "check-cli-thin.py")
_thin = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_thin)

REAL_CLOCK = re.compile(r"\b(?:ContinuousClock|SuspendingClock)\(\)")

# A parameter's default value: `name: Type = ContinuousClock()`, on a line that declares no
# property.
DEFAULT_ARGUMENT = re.compile(r"\w+\s*:\s*[^=]+=\s*$")

# Each rule: its name, a function that says whether a line of code breaks it, and what to do
# instead.
RULES = [
    (
        "unstructured-task",
        lambda code: re.search(r"\bTask(?:<[^>{]*>)?\s*(?:\([^)]*\))?\s*\{|\bTask\.detached\b|\bTask\.init\b", code),
        "use structured concurrency, such as async let or a task group",
    ),
    (
        "unchecked-sendable",
        lambda code: re.search(r"@unchecked\s+Sendable\b", code),
        "make the type Sendable the compiler can check, such as an actor, or a Mutex's state",
    ),
    (
        "task-sleep",
        lambda code: re.search(r"\bTask\.sleep\b", code),
        "sleep on a clock the caller passes, such as clock.sleep(for:)",
    ),
    (
        "real-clock",
        lambda code: any(
            not DEFAULT_ARGUMENT.search(code[:found.start()]) or re.search(r"\b(?:let|var)\b", code[:found.start()])
            for found in REAL_CLOCK.finditer(code)
        ),
        "take the clock as a parameter, with ContinuousClock() as its default",
    ),
]


def is_excluded(relative):
    """Whether a path under the packages is outside the libraries' code."""

    return any(relative.parts[:len(excluded)] == excluded for excluded in EXCLUDED)


def violations(root):
    """Each line that breaks a rule, as (path, rule, code, line number), in file order."""

    found = []

    for path in sorted(root.glob("*/Sources/**/*.swift")):
        relative = path.relative_to(root)

        if is_excluded(relative):
            continue

        for number, code in _thin.code_lines(path.read_text(encoding="utf-8")):
            for name, breaks, _ in RULES:
                if breaks(code):
                    found.append((relative.as_posix(), name, _thin.normalized(code), number))

    return found


ALLOWLIST_HEADER = """\
# Lines of the libraries that Scripts/check-concurrency.py knows break its rules, each with a
# reason. Each entry is a path under Packages, the rule, the line's code without comments or
# strings, and why it's needed, separated by tabs. Entries only go: CI fails a pull request
# that adds one.
"""


def read_allowlist(path):
    """The allow-list's entries, as (path, rule, code), each as many times as it's listed, and
    the reasons by entry."""

    entries = collections.Counter()
    reasons = {}

    if not path.exists():
        return entries, reasons

    for line in path.read_text(encoding="utf-8").split("\n"):
        if not line.strip() or line.startswith("#"):
            continue

        parts = line.split("\t")

        if len(parts) != 4 or not parts[3].strip():
            sys.exit(f"{path}: not an entry, which is a path, a rule, code and a reason separated by tabs: {line}")

        key = tuple(parts[:3])
        entries[key] += 1
        reasons[key] = parts[3]

    return entries, reasons


def write_allowlist(path, found, reasons):
    """Writes the allow-list from the lines that break a rule, keeping known reasons."""

    lines = [f"{relative}\t{name}\t{code}\t{reasons.get((relative, name, code), '')}" for relative, name, code, _ in found]

    path.write_text(ALLOWLIST_HEADER + "\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def main(arguments=None):
    parser = argparse.ArgumentParser(description="Checks the libraries' concurrency.")
    parser.add_argument("--root", type=pathlib.Path, default=DEFAULT_ROOT, help="the packages, each with Sources")
    parser.add_argument("--allowlist", type=pathlib.Path, default=DEFAULT_ALLOWLIST, help="the known lines")
    parser.add_argument("--update", action="store_true", help="write the allow-list from the sources")
    options = parser.parse_args(arguments)

    found = violations(options.root)

    if options.update:
        _, reasons = read_allowlist(options.allowlist) if options.allowlist.exists() else (None, {})
        write_allowlist(options.allowlist, found, reasons)
        print(f"Wrote {len(found)} known lines to {options.allowlist}. Give each new one a reason.")
        return 0

    allowed, _ = read_allowlist(options.allowlist)
    remaining = collections.Counter(allowed)
    advice = {name: instead for name, _, instead in RULES}
    failed = False

    for relative, name, code, number in found:
        key = (relative, name, code)

        if remaining[key] > 0:
            remaining[key] -= 1
            continue

        failed = True
        print(f"{relative}:{number}: {name}: {code}")
        print(f"  Instead, {advice[name]}.")

    for (relative, name, code), count in sorted(remaining.items()):
        if count > 0:
            failed = True
            print(f"{options.allowlist.name}: no longer found, so remove it: {relative}\t{name}\t{code}")

    if failed:
        return 1

    known = sum(allowed.values())
    print(f"No new unstructured tasks, unchecked Sendable types or real clocks ({known} known, in {options.allowlist.name}).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
