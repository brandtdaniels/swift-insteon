"""Tests for Scripts/check-device-neutral.py, on a made-up catalog and sources in a temporary
directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-device-neutral.py"

spec = importlib.util.spec_from_file_location("check_device_neutral", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

# A made-up catalog: a relay with an alias and two flags, and a modem the libraries talk through.
CATALOG = {
    "devices": [
        {"model": "9801", "name": "Garden Relay", "aliases": ["GardenLinc"], "capabilities": [{"kind": "onOff"}], "commandSets": [{"commandSet": "gardenRelay"}]},
        {"model": "9899", "name": "Window Modem", "capabilities": [{"kind": "modem"}], "commandSets": [{"commandSet": "windowModem"}]},
        {"model": "9898", "name": "Roof Hub", "capabilities": [{"kind": "modem"}, {"kind": "hub"}]},
    ],
    "commandSets": [
        {"id": "windowModem", "serialCommands": [{"name": "readIdentity"}]},
        {
            "id": "gardenRelay",
            "operatingFlags": [
                {"name": "pulse", "label": "Pulse relay"},
                {"name": "pulseBoth"},
                {"name": "heartbeat", "label": "Heartbeat"},
            ],
            "extendedSettings": {"values": [{"name": "pulseTime"}, {"name": "onLevel"}]},
        },
    ],
}

NAMING = textwrap.dedent("""\
    /// Links a Garden Relay 9801, or GardenLinc.
    let flag = "pulse"
    """)

NEUTRAL = textwrap.dedent("""\
    /// Links a relay through the Window Modem and the Roof Hub, from its HEARTBEAT and onLevel.
    let flag = "pulseOn"
    let other = "repulse" + "pulseBothWays" + "98010"
    """)


class CheckDeviceNeutralTests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.catalog = self.root / "catalog.json"
        self.catalog.write_text(json.dumps(CATALOG), encoding="utf-8")
        self.allowlist = self.root / "allowlist.txt"

    def tearDown(self):
        self.directory.cleanup()

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def run_check(self, *extra):
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main(["--root", str(self.root), "--catalog", str(self.catalog), "--allowlist", str(self.allowlist), *extra])

        return status, output.getvalue()

    def test_takes_the_words_from_the_catalog(self):
        words = check.forbidden_words(self.catalog)

        self.assertEqual({word: any_case for word, (any_case, _) in words.items()}, {
            # Product names and models, in their own case.
            "Garden Relay": False,
            "GardenLinc": False,
            "9801": False,
            # Command set ids, flag names and labels and setting names, in any case.
            "gardenRelay": True,
            "pulse": True,
            "Pulse relay": True,
            "pulseBoth": True,
            "pulseTime": True,
            "I/O Linc": True,
            "IOLinc": True,
            "IO Linc": True,
        })

    def test_leaves_the_command_sets_of_a_modem_the_libraries_talk_through(self):
        words = check.forbidden_words(self.catalog)

        self.assertNotIn("windowModem", words)

        self.write("Packages/InsteonCore/Sources/InsteonCore/Modem.swift", "let id = \"windowModem\"\n")

        status, output = self.run_check()

        self.assertEqual(status, 0, output)

    def test_matches_identifiers_and_explicit_words_in_any_case(self):
        self.write(
            "Packages/InsteonCore/Sources/InsteonCore/Relay.swift",
            "let set = \"GARDENRELAY\"\n// Turn its pulse relay flag off, and its PulseTime.\n// An iolinc, or an io linc.\n",
        )

        found = [(word, number) for _, word, number in check.violations(self.root, check.forbidden_words(self.catalog))]

        self.assertEqual(found, [("IO Linc", 3), ("IOLinc", 3), ("Pulse relay", 2), ("gardenRelay", 1), ("pulse", 2), ("pulseTime", 2)])

    def test_finds_a_word_spelled_several_ways_once(self):
        # The alias, a command set's id and a flag's name differ only in case.
        catalog = {
            "devices": [{"model": "9802", "name": "Pond Relay", "aliases": ["PondLinc"], "capabilities": []}],
            "commandSets": [{"id": "pondLinc", "operatingFlags": [{"name": "PONDLINC"}]}],
        }
        self.catalog.write_text(json.dumps(catalog), encoding="utf-8")
        self.write("Packages/InsteonCore/Sources/InsteonCore/Pond.swift", "// A pondlinc.\n")

        words = check.forbidden_words(self.catalog)
        found = check.violations(self.root, words)

        self.assertEqual(sum(1 for word in words if word.casefold() == "pondlinc"), 1)
        self.assertEqual([word.casefold() for _, word, _ in found], ["pondlinc"])

    def test_finds_each_own_case_spelling_once_per_use(self):
        # Two aliases differ only in case; each is a product name, matched in its own case.
        catalog = {"devices": [{"model": "9803", "name": "Brook Bridge", "aliases": ["BrookBridge", "BROOKBRIDGE"], "capabilities": []}], "commandSets": []}
        self.catalog.write_text(json.dumps(catalog), encoding="utf-8")
        self.write("Packages/InsteonCore/Sources/InsteonCore/One.swift", "// A BrookBridge.\n")
        self.write("Packages/InsteonCore/Sources/InsteonCore/Other.swift", "// A brookbridge, then a BROOKBRIDGE.\n")
        self.write("Packages/InsteonCore/Sources/InsteonCore/Both.swift", "// A BrookBridge and a BROOKBRIDGE.\n")

        words = check.forbidden_words(self.catalog)
        found = check.violations(self.root, words)

        self.assertEqual(words["BrookBridge"], (False, ("BROOKBRIDGE", "BrookBridge")))
        self.assertEqual([(path.rsplit("/", 1)[-1], number) for path, word, number in found if word == "BrookBridge"], [
            ("Both.swift", 1),
            ("One.swift", 1),
            ("Other.swift", 1),
        ])

    def test_matches_product_names_only_in_their_own_case(self):
        self.write("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", "// Any garden relay, as plain words.\n")

        status, output = self.run_check()

        self.assertEqual(status, 0, output)

    def test_finds_each_word_once_per_file_by_its_first_line(self):
        self.write("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", NAMING)

        found = check.violations(self.root, check.forbidden_words(self.catalog))

        self.assertEqual(found, [
            ("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", "9801", 1),
            ("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", "Garden Relay", 1),
            ("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", "GardenLinc", 1),
            ("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", "pulse", 2),
        ])

    def test_matches_only_whole_words_and_leaves_modems_hubs_and_generic_words(self):
        self.write("Packages/InsteonCLI/Sources/insteon/Relay.swift", NEUTRAL)

        status, output = self.run_check()

        self.assertEqual(status, 0, output)

    def test_reads_tests_docs_and_the_in_memory_modem(self):
        self.write("Packages/InsteonCLI/Tests/InsteonCLISupportTests/RelayTests.swift", "let name = \"IOLinc\"\n")
        self.write("Packages/InsteonCore/README.md", "Link an I/O Linc.\n")
        self.write("Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport/InMemoryModem.swift", "// pulseBoth\n")

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("Packages/InsteonCLI/Tests/InsteonCLISupportTests/RelayTests.swift:1: names IOLinc", output)
        self.assertIn("Packages/InsteonCore/README.md:1: names I/O Linc", output)
        self.assertIn("Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport/InMemoryModem.swift:1: names pulseBoth", output)

    def test_leaves_other_packages_alone(self):
        self.write("Packages/InsteonDeviceCatalog/Tests/InsteonDeviceCatalogTests/BundledTests.swift", NAMING)
        self.write("Packages/InsteonTestSupport/Sources/InsteonTestSupport/Clock.swift", NAMING)

        status, output = self.run_check()

        self.assertEqual(status, 0, output)

    def test_allows_a_listed_file_and_word_and_fails_a_stale_entry(self):
        self.write("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", "let flag = \"pulse\"\n")
        self.allowlist.write_text(
            "# Known.\n"
            "Packages/InsteonCore/Sources/InsteonCore/Relay.swift\tpulse\tWaiting to move to the catalog.\n",
            encoding="utf-8",
        )

        status, output = self.run_check()

        self.assertEqual(status, 0, output)
        self.assertIn("1 known", output)

        self.write("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", "let flag = \"other\"\n")

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("no longer found, so remove it: Packages/InsteonCore/Sources/InsteonCore/Relay.swift\tpulse", output)

    def test_refuses_an_entry_without_a_reason(self):
        self.allowlist.write_text("Packages/InsteonCore/Sources/InsteonCore/Relay.swift\tpulse\n", encoding="utf-8")

        with self.assertRaises(SystemExit):
            self.run_check()

    def test_writes_the_allowlist_keeping_reasons(self):
        self.write("Packages/InsteonCore/Sources/InsteonCore/Relay.swift", NAMING)
        self.allowlist.write_text("Packages/InsteonCore/Sources/InsteonCore/Relay.swift\tpulse\tA reason.\n", encoding="utf-8")

        status, _ = self.run_check("--update")

        self.assertEqual(status, 0)
        entries = [line for line in self.allowlist.read_text(encoding="utf-8").split("\n") if line and not line.startswith("#")]
        self.assertIn("Packages/InsteonCore/Sources/InsteonCore/Relay.swift\tpulse\tA reason.", entries)
        self.assertIn("Packages/InsteonCore/Sources/InsteonCore/Relay.swift\tGardenLinc\t", entries)
        self.assertEqual(len(entries), 4)

    def test_the_repository_passes(self):
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main([])

        self.assertEqual(status, 0, output.getvalue())


if __name__ == "__main__":
    unittest.main()
