"""Tests for Scripts/check-concurrency.py, on made-up sources in a temporary directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-concurrency.py"

spec = importlib.util.spec_from_file_location("check_concurrency", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

# A library that breaks each rule once, and a second time in an excluded place.
LOOSE = textwrap.dedent("""\
    final class Box: @unchecked Sendable {
      let clock = ContinuousClock()
      func start() {
        Task { await work() }
        Task.detached(priority: .low) { await work() }
        let typed = Task<Void, Never> { await work() }
      }
      func wait() async throws {
        try await Task.sleep(for: .seconds(1))
        try await run(clock: ContinuousClock())
      }
    }
    """)

# A library that keeps to the rules, with the rules' words in comments and strings.
TIGHT = textwrap.dedent("""\
    // Task { } and @unchecked Sendable, in a comment.
    struct Runner: Sendable {
      init(clock: any Clock<Duration> = ContinuousClock()) {}
      func run(_ clock: some Clock<Duration> = ContinuousClock(), timeout: Duration = .seconds(1)) async {
        print("Task.sleep(for:) and Task { }")
        await withTaskGroup(of: Void.self) { group in
          group.addTask { await work() }
        }
        let task: Task<Void, Never>? = nil
        _ = task
      }
    }
    """)


class CheckConcurrencyTests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name) / "Packages"
        self.allowlist = pathlib.Path(self.directory.name) / "allowlist.txt"

    def tearDown(self):
        self.directory.cleanup()

    def write(self, relative, source):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")

    def run_check(self, *extra):
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main(["--root", str(self.root), "--allowlist", str(self.allowlist), *extra])

        return status, output.getvalue()

    def test_finds_each_rule_in_the_libraries(self):
        self.write("Lib/Sources/Lib/Box.swift", LOOSE)

        found = [(name, number) for _, name, _, number in check.violations(self.root)]

        self.assertEqual(found, [
            ("unchecked-sendable", 1),
            ("real-clock", 2),
            ("unstructured-task", 4),
            ("unstructured-task", 5),
            ("unstructured-task", 6),
            ("task-sleep", 9),
            ("real-clock", 10),
        ])

    def test_accepts_a_clock_as_a_default_argument_and_structured_tasks(self):
        self.write("Lib/Sources/Lib/Runner.swift", TIGHT)

        self.assertEqual(check.violations(self.root), [])

    def test_leaves_out_tests_the_command_and_the_test_doubles(self):
        self.write("Lib/Tests/LibTests/BoxTests.swift", LOOSE)
        self.write("InsteonCLI/Sources/insteon/Box.swift", LOOSE)
        self.write("InsteonTestSupport/Sources/InsteonTestSupport/Box.swift", LOOSE)
        self.write("InsteonCLI/Sources/InsteonCLISupport/Box.swift", "final class Box: @unchecked Sendable {}\n")

        found = [(path, name) for path, name, _, _ in check.violations(self.root)]

        self.assertEqual(found, [("InsteonCLI/Sources/InsteonCLISupport/Box.swift", "unchecked-sendable")])

    def test_passes_with_every_line_allowed_and_fails_on_a_new_one(self):
        self.write("Lib/Sources/Lib/Box.swift", "final class Box: @unchecked Sendable {}\n")
        self.allowlist.write_text(
            "# Known.\nLib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.\n",
            encoding="utf-8",
        )

        self.assertEqual(self.run_check()[0], 0)

        self.write("Lib/Sources/Lib/Other.swift", "func go() { Task { } }\n")
        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("Lib/Sources/Lib/Other.swift:1: unstructured-task", output)

    def test_fails_on_an_entry_that_no_longer_matches(self):
        self.write("Lib/Sources/Lib/Box.swift", "struct Box: Sendable {}\n")
        self.allowlist.write_text(
            "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.\n",
            encoding="utf-8",
        )

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("no longer found, so remove it", output)

    def test_refuses_an_entry_without_a_reason(self):
        self.write("Lib/Sources/Lib/Box.swift", "final class Box: @unchecked Sendable {}\n")
        self.allowlist.write_text(
            "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\t\n",
            encoding="utf-8",
        )

        with self.assertRaises(SystemExit):
            self.run_check()

    def test_update_keeps_the_reasons_of_entries_that_remain(self):
        self.write("Lib/Sources/Lib/Box.swift", "final class Box: @unchecked Sendable {}\nfunc go() { Task { } }\n")
        self.allowlist.write_text(
            "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.\n",
            encoding="utf-8",
        )

        self.assertEqual(self.run_check("--update")[0], 0)

        entries = [line for line in self.allowlist.read_text(encoding="utf-8").split("\n") if line and not line.startswith("#")]

        self.assertEqual(entries, [
            "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.",
            "Lib/Sources/Lib/Box.swift\tunstructured-task\tfunc go() { Task { } }\t",
        ])


if __name__ == "__main__":
    unittest.main()
