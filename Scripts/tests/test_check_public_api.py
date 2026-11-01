"""Tests for Scripts/check-public-api.py, on made-up sources in a temporary directory.

Usage: python3 -m unittest discover -s Scripts/tests
"""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-public-api.py"

spec = importlib.util.spec_from_file_location("check_public_api", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

SOURCE = textwrap.dedent("""\
    import Foundation

    /// A store, with `public func hidden()` in a comment.
    public struct Store: Hashable, Sendable {

      public var path: String
      public private(set) var count: Int = 0
      public static let defaultName = "store"
      let secret: String

      public init(path: String) {
        self.path = path
        let local = "public var notAMember: Int"
        _ = local
      }

      public init?(_ text: String, strict: Bool = false) {
        nil
      }

      @discardableResult
      public func save(json: Data, version: Int) throws -> Bool {
        var inside = 0
        inside += 1
        return true
      }

      public static func version(json: Data) -> Int? { nil }

      func internalHelper() {}

      public subscript(index: Int) -> UInt8 { 0 }

      public struct Entry: Sendable {
        public var name: String
      }

      struct Hidden {
        public var notReachable: Int
      }

    }

    public enum StoreError: Error {
      case writeFailed(code: Int32), unreadable
      case tooLarge(limit: Int)

      public var description: String {
        switch self {
        case .writeFailed: "failed"
        case .unreadable, .tooLarge: "other"
        }
      }
    }

    enum InternalState {
      case one
    }

    public protocol Saving: Sendable {
      associatedtype Item
      func save(_ item: Item) async throws
      var isReady: Bool { get }
    }

    extension Store {
      public func load() -> Data? { nil }
      func internalLoad() {}
    }

    public typealias Address = String

    @_spi(Raw)
    public func rawSend(_ bytes: [UInt8], to address: Address) {}

    public actor Registry {
      public nonisolated let id: Int = 0
      public func register(_ store: Store) {}
    }

    public final class Box {
      public class func make() -> Box { Box() }
    }
    """)

EXPECTED = sorted([
    "struct Store",
    "var Store.path",
    "var Store.count",
    "static let Store.defaultName",
    "init Store(path:)",
    "init Store?(_:strict:)",
    "func Store.save(json:version:)",
    "static func Store.version(json:)",
    "subscript Store(index:)",
    "struct Store.Entry",
    "var Store.Entry.name",
    "enum StoreError",
    "case StoreError.writeFailed",
    "case StoreError.unreadable",
    "case StoreError.tooLarge",
    "var StoreError.description",
    "protocol Saving",
    "associatedtype Saving.Item",
    "func Saving.save(_:)",
    "var Saving.isReady",
    "func Store.load()",
    "typealias Address",
    "@_spi(Raw) func rawSend(_:to:)",
    "actor Registry",
    "let Registry.id",
    "func Registry.register(_:)",
    "class Box",
    "static func Box.make()",
])


class CheckPublicAPITests(unittest.TestCase):

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.sources = pathlib.Path(self.directory.name) / "InsteonCore"
        self.sources.mkdir()
        self.list = pathlib.Path(self.directory.name) / "api.txt"

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, source):
        (self.sources / name).write_text(source, encoding="utf-8")

    def run_check(self, *extra):
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            status = check.main(["--sources", str(self.sources), "--list", str(self.list), *extra])

        return status, output.getvalue()

    def test_lists_each_public_declaration_and_nothing_else(self):
        self.write("Store.swift", SOURCE)

        self.assertEqual(check.public_api(self.sources), EXPECTED)

    def test_passes_after_an_update(self):
        self.write("Store.swift", SOURCE)

        self.assertEqual(self.run_check("--update")[0], 0)
        self.assertEqual(self.run_check()[0], 0)
        self.assertEqual(check.read_list(self.list), EXPECTED)

    def test_fails_on_a_new_public_declaration(self):
        self.write("Store.swift", SOURCE)
        self.run_check("--update")
        self.write("More.swift", "public struct More {}\n")

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("public, not in api.txt: struct More", output)

    def test_fails_on_a_declaration_that_stopped_being_public(self):
        self.write("Store.swift", SOURCE)
        self.run_check("--update")
        self.write("Store.swift", SOURCE.replace("public static func version", "static func version"))

        status, output = self.run_check()

        self.assertEqual(status, 1)
        self.assertIn("in api.txt, not public: static func Store.version(json:)", output)

    def test_lists_overloads_that_differ_only_in_types_once(self):
        self.write("Overloads.swift", "public func send(_ value: Int) {}\npublic func send(_ value: String) {}\n")

        self.assertEqual(check.public_api(self.sources), ["func send(_:)"])

    def test_reads_parameters_across_lines(self):
        self.write("Long.swift", textwrap.dedent("""\
            public struct Long {
              public func update(
                replacing current: Data,
                from location: URL = Long.location,
                timeout: Duration
              ) async throws {}
            }
            """))

        self.assertEqual(check.public_api(self.sources), ["func Long.update(replacing:from:timeout:)", "struct Long"])


if __name__ == "__main__":
    unittest.main()
