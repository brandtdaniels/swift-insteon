"""Tests for Scripts/check-terms.py, on made-up docs and sources in a temporary directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import importlib.util
import pathlib
import re
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-terms.py"

spec = importlib.util.spec_from_file_location("check_terms", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def ruled_out(text):
    """The forms the rules find in a line of prose, in the order of the rules."""

    return [found.group(0) for pattern, _ in check.RULES if (found := re.search(pattern, text))]


class RulesTests(unittest.TestCase):

    def test_finds_each_ruled_out_form(self):
        self.assertEqual(ruled_out("INSTEON devices"), ["INSTEON"])
        self.assertEqual(ruled_out("an I2CS device"), ["I2CS"])
        self.assertEqual(ruled_out("an acknowledgement"), ["acknowledgement"])
        self.assertEqual(ruled_out("over the power line"), ["power line"])
        self.assertEqual(ruled_out("its on level"), ["on level"])
        self.assertEqual(ruled_out("the 2242 Hub"), ["2242 Hub"])
        self.assertEqual(ruled_out("the PowerLinc Modem (2413U)"), ["Modem (2413U)"])
        self.assertEqual(ruled_out("an All-Link group"), ["All-Link"])
        self.assertEqual(ruled_out("the link database"), ["link database"])
        self.assertEqual(ruled_out("the clean-up"), ["clean-up"])
        self.assertEqual(ruled_out("press the Set button"), ["Set button"])
        self.assertEqual(ruled_out("as the guide says"), ["the guide"])

    def test_accepts_the_forms_to_use(self):
        for text in [
            "Insteon devices, i2CS, an acknowledgment, the powerline, its on-level",
            "the Hub 2242, the PowerLinc Modem 2413U, an ALL-Link group, the ALL-Link database",
            "ALL-Link cleanup, the SET button, the Insteon Developer's Guide (2009)",
        ]:
            self.assertEqual(ruled_out(text), [], text)

    def test_finds_temporal_wording(self):
        self.assertEqual(ruled_out("It currently reads the database."), ["currently"])
        self.assertEqual(ruled_out("Previously it read the database."), ["Previously"])
        self.assertEqual(ruled_out("The registry no longer has it."), ["no longer"])
        self.assertEqual(ruled_out("The modem now answers."), ["now"])
        self.assertEqual(ruled_out("Now press the SET button."), ["Now"])
        self.assertEqual(ruled_out("A new option, --force, sends it."), ["new option"])
        self.assertEqual(ruled_out("The newly added flag."), ["newly"])

    def test_accepts_wording_that_isnt_temporal(self):
        for text in [
            "///   - now: The time to record, for when a device last answered.",
            "The modem reports a new link, and the buffer holds new bytes.",
            "Each call returns a new stream; the record becomes the new end.",
            "It knows the device's current state, and the record isn't in use.",
            "A snowy nowhere, a knowledgeable reader.",
        ]:
            self.assertEqual(ruled_out(text), [], text)


class ProseTests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def prose(self, name, text):
        path = self.root / name
        path.write_text(textwrap.dedent(text), encoding="utf-8")

        return [(number, line.strip()) for number, line in check.prose(path) if line.strip()]

    def test_reads_swift_comments_and_not_code_or_strings(self):
        found = self.prose("Example.swift", """\
            /// Reads the `INSTEON` database.
            let now = "currently"  // It currently waits.
            let lines = \"\"\"
              no longer
              \"\"\"
            /// ```swift
            /// let now = Date()
            /// ```
            """)

        self.assertEqual(found, [(1, "/// Reads the  database."), (2, "// It currently waits.")])

    def test_reads_markdown_and_not_code(self):
        found = self.prose("README.md", """\
            The modem `now` answers.

            ```text
            insteon --now
            ```

                indented code, no longer read
            - A list item that's read.
            """)

        self.assertEqual(found, [(1, "The modem  answers."), (8, "- A list item that's read.")])


if __name__ == "__main__":
    unittest.main()
