import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

private struct Fixture {
  let directory = try! ScratchDirectory()
  var root: URL { directory.url(for: "Tests") }

  init() {
    try! directory.makeDirectory("Tests")
  }

  func write(_ name: String, _ source: String) throws {
    try directory.write(source, to: "Tests/\(name)")
  }

  func missing() throws -> [String] {
    try TimeLimitsCheck(roots: [root], repositoryRoot: directory.url(for: "elsewhere")).missing().map { "\($0.name):\($0.line)" }
  }

  func run() throws -> (status: CheckStatus, output: String) {
    let console = RecordingConsole()
    let status = try TimeLimitsCheck(roots: [root], repositoryRoot: directory.url(for: "elsewhere")).run(in: directory.url, console: console)
    return (status, console.output)
  }
}

@Suite("check-time-limits")
struct TimeLimitsCheckTests {
  // test_finds_an_async_test_without_a_time_limit
  @Test("finds an async test without a time limit")
  func findsAsyncTestWithoutLimit() throws {
    let fixture = Fixture()
    try fixture.write(
      "ATests.swift",
      """
      import Testing

      struct ATests {

        @Test func waits() async throws {
        }

        @Test func doesntWait() throws {
        }

      }

      """
    )

    #expect(try fixture.missing() == ["waits:5"])
  }

  // test_accepts_a_time_limit_on_the_test
  @Test("accepts a time limit on the test")
  func acceptsLimitOnTest() throws {
    let fixture = Fixture()
    try fixture.write(
      "ATests.swift",
      """
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

      """
    )

    #expect(try fixture.missing() == [])
  }

  // test_accepts_a_time_limit_on_an_enclosing_suite
  @Test("accepts a time limit on an enclosing suite")
  func acceptsLimitOnSuite() throws {
    let fixture = Fixture()
    try fixture.write(
      "ATests.swift",
      """
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

      """
    )

    #expect(try fixture.missing() == ["waits:13"])
  }

  // test_doesnt_let_one_suites_limit_cover_another_in_the_same_file
  @Test("doesn't let one suite's limit cover another in the same file")
  func suitesAreSeparate() throws {
    let fixture = Fixture()
    try fixture.write(
      "ATests.swift",
      """
      @Suite(.timeLimit(.minutes(1)))
      struct ATests {
        @Test func waits() async {}
      }

      let unrelated = 1

      struct BTests {
        @Test func waits() async {}
      }

      """
    )

    #expect(try fixture.missing() == ["waits:9"])
  }

  // test_counts_an_extension_of_a_suite_with_a_time_limit
  @Test("counts an extension of a suite with a time limit")
  func countsExtension() throws {
    let fixture = Fixture()
    try fixture.write("ATests.swift", "@Suite(.timeLimit(.minutes(1)))\nstruct ATests {}\n")
    try fixture.write(
      "ATests+More.swift",
      """
      extension ATests {
        @Test func waits() async {}
      }

      extension BTests {
        @Test func waits() async {}
      }

      """
    )

    #expect(try fixture.missing() == ["waits:6"])
  }

  // test_reads_neither_comments_nor_strings
  @Test("reads neither comments nor strings")
  func readsNeitherCommentsNorStrings() throws {
    let fixture = Fixture()
    try fixture.write(
      "ATests.swift",
      ##"""
      struct ATests {
        // @Test func commented() async {}
        /* @Test func blocked() async {} /* nested */ @Test func stillBlocked() async {} */
        let text = "@Test func quoted() async {}"
        let lines = """
          @Test func inAMultilineString() async {}
          """
        let raw = #"@Test func raw() async {} "# + "\(value) @Test"
        @Test func real() async {}
      }

      """##
    )

    #expect(try fixture.missing() == ["real:9"])
  }

  // test_finds_async_in_the_effects_and_not_in_the_return_type
  @Test("finds async in the effects and not in the return type")
  func findsAsyncInEffects() throws {
    let fixture = Fixture()
    try fixture.write(
      "ATests.swift",
      """
      struct ATests {
        @Test func generic<T: Sendable>(_ value: T = 1) async throws(SomeError) where T: Equatable {}
        @Test func returnsAClosure() -> () async -> Void { {} }
      }

      """
    )

    #expect(try fixture.missing() == ["generic:2"])
  }

  // test_exits_with_status_1_when_a_test_lacks_a_limit
  @Test("ends with status 1 when a test lacks a limit")
  func statusOneWhenMissing() throws {
    let fixture = Fixture()
    try fixture.write("ATests.swift", "struct ATests {\n  @Test func waits() async {}\n}\n")

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("Tests/ATests.swift:2: waits is async and has no time limit"))
    #expect(
      output.hasSuffix(
        "1 async tests have no time limit. Add .timeLimit(.minutes(1)) to the test's @Test(...) or to its type's @Suite(...), so a test that hangs fails instead.\n"
      )
    )
  }

  // test_exits_with_status_0_when_every_async_test_has_a_limit
  @Test("ends with status 0 when every async test has a limit")
  func statusZeroWhenLimited() throws {
    let fixture = Fixture()
    try fixture.write("ATests.swift", "struct ATests {\n  @Test(.timeLimit(.minutes(1))) func waits() async {}\n}\n")

    let (status, output) = try fixture.run()

    #expect(status == .passed)
    #expect(output == "Every async test has a time limit.\n")
  }

  @Test("reads a modifier with a parenthesized part, an attribute with arguments and a backticked name")
  func readsModifiersAndNames() throws {
    let fixture = Fixture()
    try fixture.write(
      "ATests.swift",
      """
      struct ATests {
        @Test @available(macOS 13, *) public private(set) func attributed() async {}
        @Test final func `with spaces`() async {}
        @Test(.timeLimit(.minutes(1))) @MainActor func limited() async {}
      }

      """
    )

    let found = try fixture.missing()

    // The script reads `private(set) func` as `private`, then stops at `(set)`, so it skips that test.
    #expect(found == ["`with spaces`:3"])
  }

  @Test("passes on this repository")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let console = RecordingConsole()

    #expect(try TimeLimitsCheck().run(in: root, console: console) == .passed, "\(console.output)")
  }
}
