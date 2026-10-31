"""Tests for Scripts/check-cli-thin.py, on made-up sources in a temporary directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-cli-thin.py"

spec = importlib.util.spec_from_file_location("check_cli_thin", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

# A command that decides what a device does, once by each rule.
THICK = textwrap.dedent("""\
    enum DeviceCommands {
      static func on(_ known: DeviceDescription?) async throws {
        if known?.category == .dimmableLightingControl { print("dims") }
        if known?.firmwareVersion ?? 0 >= 0x41 { print("new firmware") }
        if kind == .relay { print("on/off only") }
        if engine == .i2cs { print("checksum") }
        try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.beep))
      }
    }
    """)

# A command that only words what the library says, with the rules' words in comments and
# strings.
THIN = textwrap.dedent("""\
    // A relay, category 0x02, is on/off only: kind == .relay.
    /* firmwareVersion >= 0x41 */
    enum DeviceCommands {
      static func on(_ device: Device) async throws {
        let result = try await device.turnOn(level: 50)
        print("category == 0x01 or StandardDirectCommand.on")
        print(\"\"\"
          kind == .relay
          \"\"\")
        print("Turned \\(result.group) on.")
      }
    }
    """)


class CheckCLIThinTests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name) / "insteon"
        self.root.mkdir()
        self.allowlist = pathlib.Path(self.directory.name) / "allowlist.txt"

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, text):
        (self.root / name).write_text(text, encoding="utf-8")

    def run_check(self, *extra):
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main(["--root", str(self.root), "--allowlist", str(self.allowlist), *extra])

        return status, output.getvalue()

    def rules(self):
        return sorted({name for _, name, _, _ in check.violations(self.root)})

    def test_finds_each_rule(self):
        self.write("DeviceCommands.swift", THICK)

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertEqual(self.rules(), ["category", "engine", "firmware", "group-kind", "hex-literal", "protocol-command"])
        self.assertIn("DeviceCommands.swift:3: category:", output)

    def test_ignores_comments_and_strings(self):
        self.write("DeviceCommands.swift", THIN)

        status, output = self.run_check()

        self.assertEqual(status, 0, output)
        self.assertEqual(self.rules(), [])

    def test_reads_interpolations_as_code(self):
        self.write("DeviceCommands.swift", 'print("is \\(kind == .relay ? "on" : "off")")\n')

        self.assertEqual(self.rules(), ["group-kind"])

    def test_waives_bytes_and_commands_only_for_the_raw_passthroughs(self):
        self.write("ExploreCommands.swift", THICK)

        self.assertEqual(self.rules(), ["category", "engine", "firmware", "group-kind"])

    def test_passes_known_lines_and_fails_new_ones(self):
        self.write("DeviceCommands.swift", THICK)

        status, _ = self.run_check("--update")
        self.assertEqual(status, 0)

        status, output = self.run_check()
        self.assertEqual(status, 0, output)

        self.write("SceneCommands.swift", "let command = StandardDirectCommand.on(level: 0xFF)\n")

        status, output = self.run_check()
        self.assertEqual(status, 1)
        self.assertIn("SceneCommands.swift:1: hex-literal:", output)
        self.assertIn("SceneCommands.swift:1: protocol-command:", output)
        self.assertNotIn("DeviceCommands.swift", output)

    def test_fails_on_an_entry_that_no_longer_matches(self):
        self.write("DeviceCommands.swift", THICK)
        self.run_check("--update")
        self.write("DeviceCommands.swift", THIN)

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("no longer found, so remove it", output)

    def test_counts_a_repeated_line_once_for_each_entry(self):
        line = "if kind == .relay { print() }\n"
        self.write("DeviceCommands.swift", line)
        self.run_check("--update")
        self.write("DeviceCommands.swift", line + line)

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("DeviceCommands.swift:2: group-kind:", output)

    def rules_of(self, code):
        self.write("DeviceCommands.swift", code)

        return self.rules()

    def test_finds_raw_value_comparisons(self):
        self.assertEqual(self.rules_of("if known.category.rawValue == 1 { }\n"), ["category"])
        self.assertEqual(self.rules_of("if identity.subcategory?.rawValue != 2 { }\n"), ["category"])
        self.assertEqual(self.rules_of('if group.kind.rawValue == "relay" { }\n'), ["group-kind"])
        self.assertEqual(self.rules_of("if identity.firmwareVersion.rawValue >= 65 { }\n"), ["firmware"])

    def test_finds_decimal_command_bytes(self):
        self.assertEqual(self.rules_of("let command = Command(command1: 17, command2: 255)\n"), ["command-byte"])
        self.assertEqual(self.rules_of("let command = Command(command1: received.command1, command2: level)\n"), [])

    def test_waives_decimal_command_bytes_for_the_raw_passthroughs(self):
        self.write("ExploreCommands.swift", "let command = Command(command1: 17, command2: 0)\n")

        self.assertEqual(self.rules(), [])

    def test_finds_a_kind_among_kinds(self):
        self.assertEqual(self.rules_of("if [.dimmer, .relay].contains(kind) { }\n"), ["group-kind"])
        self.assertEqual(self.rules_of("if onOffKinds.contains(group.kind) { }\n"), ["group-kind"])

    def test_allows_comparisons_with_nil(self):
        self.assertEqual(self.rules_of("if category != nil, names.catalog != nil { }\n"), [])
        self.assertEqual(self.rules_of("if rows.contains(where: { $0.category == nil }) { }\n"), [])
        self.assertEqual(self.rules_of("if nil == known?.firmwareVersion { }\n"), [])

    def test_ignores_raw_strings(self):
        self.assertEqual(self.rules_of('print(#"He said "kind == .relay" and \\(0x01)"#)\n'), [])
        self.assertEqual(self.rules_of('print(##"a "# kind == .relay"##)\n'), [])
        self.assertEqual(self.rules_of('print(#"""\n  kind == .relay "quoted"\n  """#)\n'), [])

    def test_reads_a_raw_strings_interpolations_as_code(self):
        self.assertEqual(self.rules_of('print(#"is \\#(kind == .relay ? "on" : "off")"#)\n'), ["group-kind"])

    def test_ignores_nested_block_comments(self):
        code = "/* outer /* inner */ kind == .relay\n still a comment: 0x01 */\nlet thin = true\n"

        self.assertEqual(self.rules_of(code), [])

    def test_reads_code_after_a_nested_block_comment(self):
        self.assertEqual(self.rules_of("/* a /* b */ c */ if kind == .relay { }\n"), ["group-kind"])

    def test_checks_every_root_by_its_path_from_the_roots_parent(self):
        core = pathlib.Path(self.directory.name) / "InsteonCLICore"
        core.mkdir()
        (core / "ControlText.swift").write_text("let level = 0xFF\n", encoding="utf-8")
        self.write("DeviceCommands.swift", "if kind == .relay { }\n")

        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main(["--root", str(self.root), "--root", str(core), "--allowlist", str(self.allowlist)])

        self.assertEqual(status, 1)
        self.assertIn("insteon/DeviceCommands.swift:1: group-kind:", output.getvalue())
        self.assertIn("InsteonCLICore/ControlText.swift:1: hex-literal:", output.getvalue())


if __name__ == "__main__":
    unittest.main()
