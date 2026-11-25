import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

private let source = ##"""
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

  """##

private let expected = [
  "struct Store",
  "var Store.path",
  "private(set) var Store.count",
  "static let Store.defaultName",
  "init Store(path:)",
  "init Store?(_:strict:)",
  "func Store.save(json:version:)",
  "static func Store.version(json:)",
  "subscript Store(index:)",
  "struct Store.Entry",
  "var Store.Entry.name",
  "enum StoreError",
  "case StoreError.writeFailed(code:)",
  "case StoreError.unreadable",
  "case StoreError.tooLarge(limit:)",
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
  "static func Box.make()"
].sorted { PythonText.isOrdered($0, before: $1) }

private struct Fixture {
  let directory = try! ScratchDirectory()
  var sources: URL { directory.url(for: "InsteonCore") }
  var list: URL { directory.url(for: "api.txt") }

  init() {
    try! directory.makeDirectory("InsteonCore")
  }

  func write(_ name: String, _ text: String) throws {
    try directory.write(text, to: "InsteonCore/\(name)")
  }

  func api() throws -> [String] {
    try PublicAPICheck.publicAPI(under: sources)
  }

  func run(update: Bool = false) throws -> (status: CheckStatus, output: String) {
    let console = RecordingConsole()
    let status = try PublicAPICheck(sources: sources, list: list, update: update).run(in: directory.url, console: console)
    return (status, console.output)
  }
}

@Suite("check-public-api")
struct PublicAPICheckTests {
  // test_lists_each_public_declaration_and_nothing_else
  @Test("lists each public declaration and nothing else")
  func listsEachPublicDeclaration() throws {
    let fixture = Fixture()
    try fixture.write("Store.swift", source)

    #expect(try fixture.api() == expected)
  }

  // test_passes_after_an_update
  @Test("passes after an update")
  func passesAfterUpdate() throws {
    let fixture = Fixture()
    try fixture.write("Store.swift", source)

    #expect(try fixture.run(update: true).status == .passed)
    #expect(try fixture.run().status == .passed)
    #expect(try PublicAPICheck.readList(at: fixture.list) == expected)
  }

  // test_fails_on_a_new_public_declaration
  @Test("fails on a public declaration the list doesn't have")
  func failsOnAddition() throws {
    let fixture = Fixture()
    try fixture.write("Store.swift", source)
    _ = try fixture.run(update: true)
    try fixture.write("More.swift", "public struct More {}\n")

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("public, not in api.txt: struct More"))
  }

  // test_fails_on_a_declaration_that_stopped_being_public
  @Test("fails on a declaration that stopped being public")
  func failsOnRemoval() throws {
    let fixture = Fixture()
    try fixture.write("Store.swift", source)
    _ = try fixture.run(update: true)
    try fixture.write("Store.swift", source.replacing("public static func version", with: "static func version"))

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("in api.txt, not public: static func Store.version(json:)"))
  }

  // test_lists_overloads_that_differ_only_in_types_once
  @Test("lists overloads that differ only in types once")
  func overloadsOnce() throws {
    let fixture = Fixture()
    try fixture.write("Overloads.swift", "public func send(_ value: Int) {}\npublic func send(_ value: String) {}\n")

    #expect(try fixture.api() == ["func send(_:)"])
  }

  // test_reads_parameters_across_lines
  @Test("reads parameters across lines")
  func parametersAcrossLines() throws {
    let fixture = Fixture()
    try fixture.write(
      "Long.swift",
      """
      public struct Long {
        public func update(
          replacing current: Data,
          from location: URL = Long.location,
          timeout: Duration
        ) async throws {}
      }

      """
    )

    #expect(try fixture.api() == ["func Long.update(replacing:from:timeout:)", "struct Long"])
  }

  // test_lists_the_members_of_a_public_extension_unless_they_say_otherwise
  @Test("lists the members of a public extension unless they say otherwise")
  func publicExtension() throws {
    let fixture = Fixture()
    try fixture.write(
      "Extension.swift",
      """
      public extension Store {
        func load() -> Data? { nil }
        static var shared: Store { Store() }
        internal func helper() {}
        private func hidden() {}
        fileprivate var cache: Int { 0 }
        package func packaged() {}
      }

      extension Store {
        func notPublic() {}
        public func stated() {}
      }

      """
    )

    #expect(try fixture.api() == ["func Store.load()", "func Store.stated()", "static var Store.shared"])
  }

  // test_reads_members_on_a_types_opening_line
  @Test("reads members on a type's opening line")
  func membersOnOpeningLine() throws {
    let fixture = Fixture()
    try fixture.write("OneLine.swift", "public struct S { public func f() {} }\nstruct T { public func g() {} }\n")

    #expect(try fixture.api() == ["func S.f()", "struct S"])
  }

  // test_reads_declarations_separated_by_semicolons
  @Test("reads declarations separated by semicolons")
  func semicolons() throws {
    let fixture = Fixture()
    try fixture.write("Semicolons.swift", "public struct S {\n  public var a: Int; public var b: Int; var c: Int\n}\n")

    #expect(try fixture.api() == ["struct S", "var S.a", "var S.b"])
  }

  // test_lists_enum_cases_with_their_associated_value_labels
  @Test("lists enum cases with their associated value labels")
  func enumCases() throws {
    let fixture = Fixture()
    try fixture.write(
      "Cases.swift",
      """
      public enum Reply: UInt8 {
        case ack = 0x06, nak = 0x15
      }

      public enum Event {
        case sent(Data, to: Address), heard(_ level: Int)
        case idle
      }

      """
    )

    #expect(
      try fixture.api() == [
        "case Event.heard(_:)", "case Event.idle", "case Event.sent(_:to:)", "case Reply.ack", "case Reply.nak",
        "enum Event", "enum Reply"
      ]
    )
  }

  // test_marks_a_restricted_setter
  @Test("marks a restricted setter")
  func restrictedSetter() throws {
    let fixture = Fixture()
    try fixture.write(
      "Setter.swift",
      """
      public struct S {
        public private(set) var count: Int
        public internal(set) var name: String
        public var open: Bool
      }

      """
    )

    #expect(try fixture.api() == ["internal(set) var S.name", "private(set) var S.count", "struct S", "var S.open"])
  }

  // test_reads_labels_after_a_function_type
  @Test("reads labels after a function type")
  func labelsAfterFunctionType() throws {
    let fixture = Fixture()
    try fixture.write(
      "Closures.swift",
      """
      public func identify(
        _ hubs: [Hub],
        sendsCredentials: @Sendable (Hub) async throws -> Bool,
        onResult: @Sendable (Hub, Result<Int, Error>) -> Void = { _, _ in }
      ) {}

      """
    )

    #expect(try fixture.api() == ["func identify(_:sendsCredentials:onResult:)"])
  }

  @Test("prints the success line with the count and the list's name")
  func successLine() throws {
    let fixture = Fixture()
    try fixture.write("Store.swift", "public struct S {}\n")
    _ = try fixture.run(update: true)

    #expect(try fixture.run().output == "InsteonCore's public API matches its list (1 declarations, in api.txt).\n")
  }

  @Test("matches the committed list byte for byte")
  func repositoryList() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = try ScratchDirectory()
    let written = directory.url(for: "list.txt")

    #expect(try PublicAPICheck(list: written, update: true).run(in: root, console: RecordingConsole()) == .passed)
    #expect(try Data(contentsOf: written) == Data(contentsOf: root.appendingPathComponent("Scripts/insteoncore-public-api.txt")))
    #expect(try PublicAPICheck().run(in: root, console: RecordingConsole()) == .passed)
  }
}
