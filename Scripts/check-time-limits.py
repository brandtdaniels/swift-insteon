#!/usr/bin/env python3
"""Checks that every async test has a time limit.

Usage: python3 Scripts/check-time-limits.py [--root DIR ...]

An async test that waits on something that never comes, such as a clock that's never advanced,
hangs until CI's job limit rather than failing. So each `@Test` whose function is `async` needs
a `.timeLimit(...)` trait, in its own `@Test(...)` or in the `@Suite(...)` of a type that
encloses it. A test in an extension counts the `@Suite` of the extended type, when that type is
declared under one of the roots.

It reads the Swift files under `Packages/*/Tests` by default, leaving out comments and string
literals, and prints each async test without a time limit. It exits with status 1 if it finds
any.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

TYPE_KEYWORDS = r"(?:struct|class|actor|enum|extension)"

# Modifiers that may come between a declaration's attributes and its keyword.
MODIFIERS = r"(?:public|package|internal|fileprivate|private|open|final|nonisolated|indirect|static|mutating|override|required|convenience)"


def blanked(text):
    """The text with comments and the insides of string literals turned into spaces.

    Newlines are kept, and so is every other character's position, so an index into the result
    is an index into the text and line numbers match. A string's quotes are kept, and so is
    the code of its interpolations.
    """

    out = list(text)
    length = len(text)
    index = 0

    def blank(start, end):
        for position in range(start, end):
            if out[position] != "\n":
                out[position] = " "

    def skip_string(index, hashes, multiline):
        """Scans a string's contents from `index`; returns the index after its closing quotes."""

        closing = ('"""' if multiline else '"') + "#" * hashes
        escape = "\\" + "#" * hashes

        while index < length:
            if text.startswith(escape + "(", index):
                blank(index, index + len(escape) + 1)
                index = skip_code(index + len(escape) + 1, inside_interpolation=True)
                continue

            if text.startswith(escape, index):
                blank(index, min(index + len(escape) + 1, length))
                index += len(escape) + 1
                continue

            if text.startswith(closing, index):
                return index + len(closing)

            if text[index] == "\n" and not multiline:
                return index

            blank(index, index + 1)
            index += 1

        return index

    def skip_code(index, inside_interpolation=False):
        """Scans code from `index`; inside an interpolation, stops after its closing parenthesis."""

        depth = 0

        while index < length:
            if text.startswith("//", index):
                end = text.find("\n", index)
                end = length if end < 0 else end
                blank(index, end)
                index = end
                continue

            if text.startswith("/*", index):
                start = index
                nesting = 0

                while index < length:
                    if text.startswith("/*", index):
                        nesting += 1
                        index += 2
                    elif text.startswith("*/", index):
                        nesting -= 1
                        index += 2

                        if nesting == 0:
                            break
                    else:
                        index += 1

                blank(start, index)
                continue

            opening = re.match(r'(#*)("""|")', text[index:index + 64])

            if opening and (opening.group(1) or text[index] == '"'):
                index = skip_string(index + opening.end(), len(opening.group(1)), opening.group(2) == '"""')
                continue

            character = text[index]

            if inside_interpolation:
                if character == "(":
                    depth += 1
                elif character == ")":
                    if depth == 0:
                        return index + 1

                    depth -= 1

            index += 1

        return index

    skip_code(0)

    return "".join(out)


def balanced(code, index, opening="(", closing=")"):
    """The index after the bracket that closes the one at `index`."""

    depth = 0

    for position in range(index, len(code)):
        if code[position] == opening:
            depth += 1
        elif code[position] == closing:
            depth -= 1

            if depth == 0:
                return position + 1

    return len(code)


def skip_attributes_and_modifiers(code, index):
    """The index after any attributes, with their arguments, and modifiers from `index`."""

    while True:
        space = re.compile(r"\s*").match(code, index)
        index = space.end()

        attribute = re.compile(r"@[\w.]+").match(code, index)

        if attribute:
            index = attribute.end()

            if code.startswith("(", index):
                index = balanced(code, index)

            continue

        modifier = re.compile(MODIFIERS + r"(?:\(\w+\))?\b").match(code, index)

        if modifier:
            index = modifier.end()
            continue

        return index


class TypeScope:
    """A type declaration or extension, and the span of its body."""

    def __init__(self, name, start, end, has_time_limit):
        self.name = name
        self.start = start
        self.end = end
        self.has_time_limit = has_time_limit


def suite_has_time_limit(code, attributes_start, keyword_start):
    """Whether a `@Suite(...)` among the attributes before a declaration sets a time limit."""

    index = attributes_start

    while index < keyword_start:
        found = re.compile(r"@Suite\b").search(code, index, keyword_start)

        if not found:
            return False

        index = found.end()

        if code.startswith("(", index):
            end = balanced(code, index)

            if ".timeLimit(" in code[index:end] or "timeLimit(" in code[index:end]:
                return True

            index = end

    return False


def type_scopes(code):
    """Each type declaration and extension in the code, with whether its `@Suite` has a time limit."""

    scopes = []

    for found in re.finditer(r"\b" + TYPE_KEYWORDS + r"\s+([A-Za-z_][\w.]*)", code):
        # The declaration's attributes come after the end of the previous declaration or
        # statement, which is at most a line or two back; look back to the last brace.
        before = max(code.rfind("{", 0, found.start()), code.rfind("}", 0, found.start()))
        attributes_start = before + 1
        prefix = code[attributes_start:found.start()]

        # Only attributes and modifiers may come between that point and the keyword; anything
        # else, such as `let x = 1` on an earlier line, ends before the attributes start.
        statements = list(re.finditer(r"\n", prefix))
        start = attributes_start

        for newline in statements:
            line_end = attributes_start + newline.end()

            if skip_attributes_and_modifiers(code, start) < line_end and code[start:line_end].strip():
                start = line_end

        if skip_attributes_and_modifiers(code, start) != found.start():
            continue

        body = code.find("{", found.end())

        if body < 0:
            continue

        end = balanced(code, body, "{", "}")
        scopes.append(TypeScope(found.group(1).split(".")[-1], body, end, suite_has_time_limit(code, start, found.start())))

    return scopes


def tests(code):
    """Each `@Test` function: its name, whether it's async, whether its own trait sets a time
    limit, and the index of its `@Test`."""

    found = []

    for attribute in re.finditer(r"@Test\b", code):
        index = attribute.end()
        arguments = ""

        if code.startswith("(", index):
            end = balanced(code, index)
            arguments = code[index:end]
            index = end

        index = skip_attributes_and_modifiers(code, index)
        function = re.compile(r"func\s+(\w+|`[^`]+`)\s*").match(code, index)

        if not function:
            continue

        index = function.end()

        if code.startswith("<", index):
            index = balanced(code, index, "<", ">")

        index = code.find("(", index)

        if index < 0:
            continue

        parameters_end = balanced(code, index)
        body = code.find("{", parameters_end)
        effects = code[parameters_end:body if body >= 0 else len(code)]
        # The effects come before any return type, which may be a closure type that's async.
        effects = effects.split("->")[0]

        found.append((
            function.group(1),
            re.search(r"\basync\b", effects) is not None,
            "timeLimit(" in arguments,
            attribute.start(),
        ))

    return found


def missing(roots):
    """Each async test without a time limit, as (path, line number, name), in file order."""

    if isinstance(roots, pathlib.Path):
        roots = [roots]

    files = []

    for root in roots:
        for path in sorted(root.rglob("*.swift")):
            files.append((root, path, blanked(path.read_text(encoding="utf-8"))))

    # Types declared under a `@Suite` with a time limit, by name, for the extensions of them.
    limited_types = set()
    scopes_by_file = {}

    for root, path, code in files:
        scopes = type_scopes(code)
        scopes_by_file[path] = scopes

        for scope in scopes:
            if scope.has_time_limit:
                limited_types.add(scope.name)

    found = []

    for root, path, code in files:
        scopes = scopes_by_file[path]

        for name, is_async, has_own_limit, position in tests(code):
            if not is_async or has_own_limit:
                continue

            enclosing = [scope for scope in scopes if scope.start < position < scope.end]

            if any(scope.has_time_limit or scope.name in limited_types for scope in enclosing):
                continue

            line = code.count("\n", 0, position) + 1
            found.append((display_path(path, root), line, name))

    return found


def display_path(path, root):
    """A path from the repository's root, or from its root's parent outside the repository."""

    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.relative_to(root.parent).as_posix()


def default_roots():
    """Every package's `Tests` directory."""

    return sorted((ROOT / "Packages").glob("*/Tests"))


def main(arguments=None):
    parser = argparse.ArgumentParser(description="Checks that every async test has a time limit.")
    parser.add_argument("--root", type=pathlib.Path, action="append", help="tests to check; may be given more than once")
    options = parser.parse_args(arguments)

    found = missing(options.root or default_roots())

    for relative, line, name in found:
        print(f"{relative}:{line}: {name} is async and has no time limit")

    if found:
        print(
            f"{len(found)} async tests have no time limit. Add .timeLimit(.minutes(1)) to the test's "
            "@Test(...) or to its type's @Suite(...), so a test that hangs fails instead."
        )

        return 1

    print("Every async test has a time limit.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
