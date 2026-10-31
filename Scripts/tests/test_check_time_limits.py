"""Tests for Scripts/check-time-limits.py, on made-up tests in a temporary directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-time-limits.py"

spec = importlib.util.spec_from_file_location("check_time_limits", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class CheckTimeLimitsTests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name) / "Tests"
        self.root.mkdir()

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, source):
        (self.root / name).write_text(textwrap.dedent(source), encoding="utf-8")

    def missing(self):
        return [(name, line) for _, line, name in check.missing(self.root)]

    def test_finds_an_async_test_without_a_time_limit(self):
        self.write("ATests.swift", """\
            import Testing

            struct ATests {

              @Test func waits() async throws {
              }

              @Test func doesntWait() throws {
              }

            }
            """)

        self.assertEqual(self.missing(), [("waits", 5)])

    def test_accepts_a_time_limit_on_the_test(self):
        self.write("ATests.swift", """\
            struct ATests {
              @Test(.timeLimit(.minutes(1))) func waits() async {}
              @Test("Named", .timeLimit(.minutes(1))) func named() async {}
              @Test(.timeLimit(.minutes(1)), arguments: [1, 2]) func each(value: Int) async {}
              @Test(
                "Over lines",
                .timeLimit(.minutes(1))
              )
              func overLines() async throws {}
            }
            """)

        self.assertEqual(self.missing(), [])

    def test_accepts_a_time_limit_on_an_enclosing_suite(self):
        self.write("ATests.swift", """\
            /// Tests, with `@Suite` in their comment.
            @Suite(.serialized, .timeLimit(.minutes(1)))
            @MainActor
            final class ATests {
              @Test func waits() async {}
              struct Nested {
                @Test func alsoWaits() async {}
              }
            }

            @Suite(.serialized)
            struct BTests {
              @Test func waits() async {}
            }
            """)

        self.assertEqual(self.missing(), [("waits", 13)])

    def test_doesnt_let_one_suites_limit_cover_another_in_the_same_file(self):
        self.write("ATests.swift", """\
            @Suite(.timeLimit(.minutes(1)))
            struct ATests {
              @Test func waits() async {}
            }

            let unrelated = 1

            struct BTests {
              @Test func waits() async {}
            }
            """)

        self.assertEqual(self.missing(), [("waits", 9)])

    def test_counts_an_extension_of_a_suite_with_a_time_limit(self):
        self.write("ATests.swift", """\
            @Suite(.timeLimit(.minutes(1)))
            struct ATests {}
            """)
        self.write("ATests+More.swift", """\
            extension ATests {
              @Test func waits() async {}
            }

            extension BTests {
              @Test func waits() async {}
            }
            """)

        self.assertEqual(self.missing(), [("waits", 6)])

    def test_reads_neither_comments_nor_strings(self):
        self.write("ATests.swift", """\
            struct ATests {
              // @Test func commented() async {}
              /* @Test func blocked() async {} /* nested */ @Test func stillBlocked() async {} */
              let text = "@Test func quoted() async {}"
              let lines = \"\"\"
                @Test func inAMultilineString() async {}
                \"\"\"
              let raw = #"@Test func raw() async {} "# + "\\(value) @Test"
              @Test func real() async {}
            }
            """)

        self.assertEqual(self.missing(), [("real", 9)])

    def test_finds_async_in_the_effects_and_not_in_the_return_type(self):
        self.write("ATests.swift", """\
            struct ATests {
              @Test func generic<T: Sendable>(_ value: T = 1) async throws(SomeError) where T: Equatable {}
              @Test func returnsAClosure() -> () async -> Void { {} }
            }
            """)

        self.assertEqual(self.missing(), [("generic", 2)])

    def test_exits_with_status_1_when_a_test_lacks_a_limit(self):
        self.write("ATests.swift", "struct ATests {\n  @Test func waits() async {}\n}\n")

        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main(["--root", str(self.root)])

        self.assertEqual(status, 1)
        self.assertIn("Tests/ATests.swift:2: waits is async and has no time limit", output.getvalue())

    def test_exits_with_status_0_when_every_async_test_has_a_limit(self):
        self.write("ATests.swift", "struct ATests {\n  @Test(.timeLimit(.minutes(1))) func waits() async {}\n}\n")

        with contextlib.redirect_stdout(io.StringIO()):
            status = check.main(["--root", str(self.root)])

        self.assertEqual(status, 0)


if __name__ == "__main__":
    unittest.main()
