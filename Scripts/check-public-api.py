#!/usr/bin/env python3
"""Checks that InsteonCore's public declarations match the list committed beside this script.

Usage: python3 Scripts/check-public-api.py [--sources DIR] [--list FILE] [--update]

InsteonCore is what a front end, such as an app or the `insteon` command, builds on, so a
change to what it makes public is a change to every front end. The list,
`Scripts/insteoncore-public-api.txt` by default, holds one line per public declaration, such as
`struct ProductCatalogStore`, `func ProductCatalogStore.save(json:version:)` or
`case ProductCatalogStoreError.writeFailed`, so a pull request that adds, removes or renames
one shows it in the list's diff, where a reviewer sees it.

It reads the Swift files under `Packages/InsteonCore/Sources/InsteonCore`, leaving out comments
and string literals, and finds each declaration marked `public` or `open`, each member of a
`public` or `open` extension that doesn't say `internal`, `fileprivate`, `private` or
`package`, each requirement of a public protocol, and each case of a public enum. A declaration
in a type that isn't public is left out, since nothing outside the module reaches it. A
declaration a module opts into with `@_spi(Name)` is listed with that attribute, since it's
still public to a caller that opts in.

The list holds names, not whole signatures: functions, initializers, subscripts and enum cases
by their argument labels, such as `case KeepAwakeEvent.notSent(_:reason:)`, and properties by name,
with a setter that isn't public marked, such as `private(set) var DeviceRegistry.catalog`. So
overloads that differ only in their types share a line, and a change to a type, a default value
or a conformance doesn't show in the list.

It prints each declaration that isn't in the list and each line of the list that matches none,
and exits with status 1 if there's either. `--update` writes the list from the sources;
commit it with the change that made it differ.
"""

import argparse
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_SOURCES = ROOT / "Packages" / "InsteonCore" / "Sources" / "InsteonCore"

DEFAULT_LIST = ROOT / "Scripts" / "insteoncore-public-api.txt"

# The comment and string stripper check-cli-thin.py uses.
_spec = importlib.util.spec_from_file_location("check_cli_thin", ROOT / "Scripts" / "check-cli-thin.py")
_thin = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_thin)

TYPE_KEYWORDS = {"struct", "enum", "class", "actor", "protocol", "extension"}

# Modifiers that keep a member of a `public` extension from being public.
RESTRICTING = {"internal", "fileprivate", "private", "package"}

DECLARATION = re.compile(
    r"\b(struct|enum|class|actor|protocol|extension|func|var|let|init|subscript|case|typealias|associatedtype)\b"
)

IDENTIFIER = r"`?[A-Za-z_][A-Za-z0-9_]*`?"

# Modifiers that can come before a declaration's keyword.
MODIFIER = re.compile(
    r"(?:@\w+(?:\([^)]*\))?|public|open|internal|fileprivate|private|package|static|class|final|"
    r"mutating|nonmutating|nonisolated|override|convenience|required|indirect|lazy|weak|unowned|"
    r"dynamic|optional|isolated|distributed|consuming|borrowing|"
    r"(?:public|internal|fileprivate|private|package)\(set\))$"
)


class Context:
    """A type or extension whose body declares members."""

    def __init__(self, kind, name, is_public, spi, body_depth, members_public=False):
        self.kind = kind
        self.name = name
        self.is_public = is_public
        self.spi = spi
        self.body_depth = body_depth
        # A `public` or `open` extension makes its members public unless they say otherwise.
        self.members_public = members_public


def code_text(text):
    """The text's code without comments or string literals, its lines kept."""

    return "\n".join(code for _, code in _thin.code_lines(text))


def modifiers_before(code, start):
    """The modifiers and attributes written before the keyword at `start`, as a list, reading
    back over whole words and over lines that hold only attributes."""

    words = []
    index = start

    while True:
        before = code[:index].rstrip(" \t")
        line_start = before.rfind("\n") + 1
        segment = before[line_start:]
        tokens = re.findall(r"@\w+(?:\([^)]*\))?|\w+\(set\)|\w+", segment)
        taken = []

        for token in reversed(tokens):
            if not MODIFIER.match(token):
                # Another token, such as a type's opening line or `;`, ends the modifiers.
                return list(reversed(taken)) + words

            taken.append(token)

        words = list(reversed(taken)) + words

        # Every word on the line was a modifier: keep reading the line above, which may hold
        # attributes such as `@_spi(Raw)` or `@discardableResult`.
        if line_start == 0:
            return words

        index = line_start - 1


def balanced(code, start):
    """The text inside the parentheses that open at `start`, and the index after them."""

    depth = 0

    for index in range(start, len(code)):
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1

            if depth == 0:
                return code[start + 1:index], index + 1

    return code[start + 1:], len(code)


def split_top_level(text):
    """Splits a parameter list at the commas outside brackets."""

    parts, depth, current = [], 0, []

    for index, character in enumerate(text):
        if character in "([<{":
            depth += 1
        elif character in ")]>}" and not (character == ">" and text[index - 1:index] == "-"):
            # The `>` of a function type's `->` closes nothing.
            depth -= 1

        if character == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(character)

    if "".join(current).strip():
        parts.append("".join(current))

    return parts


def labels(parameters):
    """The argument labels of a parameter list, such as `json:version:` or `_:`."""

    result = []

    for parameter in split_top_level(parameters):
        if ":" not in parameter:
            # An enum case's unlabeled associated value, such as the `Int` in `case code(Int)`.
            result.append("_:")
            continue

        names = re.findall(IDENTIFIER, parameter.split(":")[0])
        names = [name for name in names if name not in ("inout", "borrowing", "consuming", "isolated", "sending")]

        if names:
            result.append(names[0].strip("`") + ":")

    return "".join(result)


def declarations(text):
    """Each public declaration in a file's text, as its line in the list."""

    code = code_text(text)
    events = [(match.start(), "{") for match in re.finditer(r"\{", code)]
    events += [(match.start(), "}") for match in re.finditer(r"\}", code)]
    events += [(match.start(), match) for match in DECLARATION.finditer(code)]
    events.sort(key=lambda event: event[0])

    found = set()
    stack = []
    depth = 0
    pending = None

    for position, event in events:
        if event == "{":
            depth += 1

            if pending is not None:
                pending.body_depth = depth
                stack.append(pending)
                pending = None

            continue

        if event == "}":
            if stack and stack[-1].body_depth == depth:
                stack.pop()

            depth -= 1
            continue

        keyword = event.group(1)
        context = stack[-1] if stack else None
        at_member_level = (context is None and depth == 0) or (context is not None and depth == context.body_depth)

        if not at_member_level:
            continue

        # `case` and `let` in a pattern, or `class` used as a modifier, aren't declarations.
        rest = code[event.end():]

        if keyword == "class" and re.match(r"\s+(func|var|let|subscript|override)\b", rest):
            continue

        if keyword == "case" and (context is None or context.kind != "enum"):
            continue

        modifiers = modifiers_before(code, position)
        spi = next((word for word in modifiers if word.startswith("@_spi")), None) or (context.spi if context else None)
        explicit = "public" in modifiers or "open" in modifiers
        is_static = "static" in modifiers or "class" in modifiers

        restricted = any(word in RESTRICTING for word in modifiers)

        if context is None:
            is_public = explicit
        elif context.kind == "protocol":
            is_public = context.is_public
        elif keyword == "case":
            is_public = context.is_public
        elif context.members_public:
            is_public = explicit or not restricted
        else:
            is_public = explicit and context.is_public

        owner = f"{context.name}." if context else ""

        if keyword in TYPE_KEYWORDS:
            name = re.match(r"\s+([A-Za-z_][A-Za-z0-9_.]*)", rest)

            if not name:
                continue

            if keyword == "extension":
                # An extension isn't listed itself. Its members are public when they say so, or
                # when the extension is `public` or `open` and they don't say otherwise.
                pending = Context("extension", name.group(1), True, spi, None, members_public=explicit)
                continue

            qualified = owner + name.group(1)
            pending = Context(keyword, qualified, is_public, spi, None, members_public=False)

            if is_public:
                found.add(entry(spi, keyword, qualified))

            continue

        if not is_public:
            continue

        setter = next((word for word in modifiers if word.endswith("(set)") and not word.startswith(("public", "open"))), None)
        prefix = ("static " if is_static else "")

        if keyword == "func":
            name = re.match(r"\s+(" + IDENTIFIER + r"|[^\s(<]+)\s*(?:<[^>]*>)?\s*\(", rest)

            if name:
                parameters, _ = balanced(code, event.end() + name.end() - 1)
                found.add(entry(spi, prefix + "func", f"{owner}{name.group(1).strip('`')}({labels(parameters)})"))

        elif keyword in ("init", "subscript"):
            opening = re.match(r"\s*[?!]?\s*(?:<[^>]*>)?\s*\(", rest)

            if opening:
                parameters, _ = balanced(code, event.end() + opening.end() - 1)
                failable = "?" if re.match(r"\s*\?", rest) else ""
                found.add(entry(spi, prefix + keyword, f"{context.name if context else ''}{failable}({labels(parameters)})"))

        elif keyword in ("var", "let"):
            name = re.match(r"\s+(" + IDENTIFIER + ")", rest)

            if name:
                kind = (setter + " " if setter else "") + prefix + keyword
                found.add(entry(spi, kind, owner + name.group(1).strip("`")))

        elif keyword in ("typealias", "associatedtype"):
            name = re.match(r"\s+(" + IDENTIFIER + ")", rest)

            if name:
                found.add(entry(spi, keyword, owner + name.group(1).strip("`")))

        elif keyword == "case":
            line = rest.split("\n")[0]

            for element in split_top_level(line):
                element = element.split("=")[0]
                name = re.match(r"\s*(" + IDENTIFIER + r")\s*(\(.*\))?", element)

                if name:
                    values = f"({labels(name.group(2)[1:-1])})" if name.group(2) else ""
                    found.add(entry(spi, "case", owner + name.group(1).strip("`") + values))

    return found


def entry(spi, kind, name):
    """A declaration's line in the list."""

    return f"{spi + ' ' if spi else ''}{kind} {name}"


def public_api(sources):
    """Every public declaration under a directory, sorted."""

    found = set()

    for path in sorted(sources.rglob("*.swift")):
        found |= declarations(path.read_text(encoding="utf-8"))

    return sorted(found)


LIST_HEADER = """\
# InsteonCore's public declarations, as Scripts/check-public-api.py lists them. CI fails when the
# sources and this list differ, so a change to InsteonCore's public API shows here in review.
# After a deliberate change, run `python3 Scripts/check-public-api.py --update` and commit this
# file with it.
"""


def read_list(path):
    """The list's declarations."""

    if not path.exists():
        return []

    return [line for line in path.read_text(encoding="utf-8").split("\n") if line.strip() and not line.startswith("#")]


def main(arguments=None):
    parser = argparse.ArgumentParser(description="Checks InsteonCore's public API against its list.")
    parser.add_argument("--sources", type=pathlib.Path, default=DEFAULT_SOURCES, help="InsteonCore's sources")
    parser.add_argument("--list", type=pathlib.Path, default=DEFAULT_LIST, help="the committed list")
    parser.add_argument("--update", action="store_true", help="write the list from the sources")
    options = parser.parse_args(arguments)

    found = public_api(options.sources)

    if options.update:
        options.list.write_text(LIST_HEADER + "\n".join(found) + ("\n" if found else ""), encoding="utf-8")
        print(f"Wrote {len(found)} public declarations to {options.list}.")
        return 0

    listed = read_list(options.list)
    added = sorted(set(found) - set(listed))
    removed = sorted(set(listed) - set(found))

    for line in added:
        print(f"public, not in {options.list.name}: {line}")

    for line in removed:
        print(f"in {options.list.name}, not public: {line}")

    if added or removed:
        print(
            "InsteonCore's public API differs from its list. If the change is deliberate, run "
            "`python3 Scripts/check-public-api.py --update` and commit the list with it."
        )
        return 1

    print(f"InsteonCore's public API matches its list ({len(found)} declarations, in {options.list.name}).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
