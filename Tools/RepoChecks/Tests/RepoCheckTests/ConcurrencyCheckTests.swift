import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

// A library that breaks each rule once.
private let loose = """
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

  """

// A library that keeps to the rules, with the rules' words in comments and strings.
private let tight = """
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

  """

private struct Fixture {
  let directory = try! ScratchDirectory()
  var packages: URL { directory.url(for: "Packages") }
  var allowlist: URL { directory.url(for: "allowlist.txt") }

  func write(_ relative: String, _ source: String) throws {
    try directory.write(source, to: "Packages/\(relative)")
  }

  func run(update: Bool = false) throws -> (status: CheckStatus, output: String) {
    let console = RecordingConsole()
    let status = try ConcurrencyCheck(packages: packages, allowlist: allowlist, update: update).run(in: directory.url, console: console)
    return (status, console.output)
  }

  func violations() throws -> [ConcurrencyViolation] {
    try ConcurrencyCheck.violations(in: packages)
  }
}

@Suite("check-concurrency")
struct ConcurrencyCheckTests {
  // test_finds_each_rule_in_the_libraries
  @Test("finds each rule in the libraries")
  func findsEachRule() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Box.swift", loose)

    let found = try fixture.violations().map { "\($0.rule):\($0.line)" }

    #expect(
      found == [
        "unchecked-sendable:1", "real-clock:2", "unstructured-task:4", "unstructured-task:5",
        "unstructured-task:6", "task-sleep:9", "real-clock:10"
      ]
    )
  }

  // test_accepts_a_clock_as_a_default_argument_and_structured_tasks
  @Test("accepts a clock as a default argument and structured tasks")
  func acceptsDefaultClock() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Runner.swift", tight)

    #expect(try fixture.violations() == [])
  }

  // test_leaves_out_tests_the_command_and_the_test_doubles
  @Test("leaves out tests, the command and the test doubles")
  func leavesOutExcluded() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Tests/LibTests/BoxTests.swift", loose)
    try fixture.write("InsteonCLI/Sources/insteon/Box.swift", loose)
    try fixture.write("InsteonTestSupport/Sources/InsteonTestSupport/Box.swift", loose)
    try fixture.write("InsteonCLI/Sources/InsteonCLISupport/Box.swift", "final class Box: @unchecked Sendable {}\n")

    let found = try fixture.violations().map { "\($0.path) \($0.rule)" }

    #expect(found == ["InsteonCLI/Sources/InsteonCLISupport/Box.swift unchecked-sendable"])
  }

  // test_passes_with_every_line_allowed_and_fails_on_a_new_one
  @Test("passes with every line allowed and fails on a new one")
  func passesAllowedFailsNew() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Box.swift", "final class Box: @unchecked Sendable {}\n")
    try fixture.directory.write(
      "# Known.\nLib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.\n",
      to: "allowlist.txt"
    )

    #expect(try fixture.run().status == .passed)

    try fixture.write("Lib/Sources/Lib/Other.swift", "func go() { Task { } }\n")
    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("Lib/Sources/Lib/Other.swift:1: unstructured-task"))
  }

  // test_fails_on_an_entry_that_no_longer_matches
  @Test("fails on an entry that no longer matches")
  func failsOnStaleEntry() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Box.swift", "struct Box: Sendable {}\n")
    try fixture.directory.write(
      "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.\n",
      to: "allowlist.txt"
    )

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("no longer found, so remove it"))
  }

  // test_refuses_an_entry_without_a_reason
  @Test("refuses an entry without a reason")
  func refusesEntryWithoutReason() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Box.swift", "final class Box: @unchecked Sendable {}\n")
    try fixture.directory.write(
      "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\t\n",
      to: "allowlist.txt"
    )

    #expect(throws: CheckFailure.self) { try fixture.run() }
  }

  // test_update_keeps_the_reasons_of_entries_that_remain
  @Test("update keeps the reasons of entries that remain")
  func updateKeepsReasons() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Box.swift", "final class Box: @unchecked Sendable {}\nfunc go() { Task { } }\n")
    try fixture.directory.write(
      "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.\n",
      to: "allowlist.txt"
    )

    let (status, output) = try fixture.run(update: true)

    #expect(status == .passed)
    #expect(output == "Wrote 2 known lines to \(fixture.allowlist.path). Give each new one a reason.\n")
    let entries = try String(contentsOf: fixture.allowlist, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: true)
      .filter { !$0.hasPrefix("#") }.map(String.init)
    #expect(
      entries == [
        "Lib/Sources/Lib/Box.swift\tunchecked-sendable\tfinal class Box: @unchecked Sendable {}\tA lock guards it.",
        "Lib/Sources/Lib/Box.swift\tunstructured-task\tfunc go() { Task { } }\t"
      ]
    )
  }

  @Test("prints each violation with its advice and the success line with the known count")
  func messages() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Box.swift", "func go() { Task.sleep(nanoseconds: 1) }\n")

    #expect(
      try fixture.run().output == """
        Lib/Sources/Lib/Box.swift:1: task-sleep: func go() { Task.sleep(nanoseconds: 1) }
          Instead, sleep on a clock the caller passes, such as clock.sleep(for:).

        """
    )

    try fixture.write("Lib/Sources/Lib/Box.swift", tight)
    #expect(
      try fixture.run().output
        == "No new unstructured tasks, unchecked Sendable types or real clocks (0 known, in allowlist.txt).\n"
    )
  }

  @Test("passes on this repository")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let console = RecordingConsole()

    #expect(try ConcurrencyCheck().run(in: root, console: console) == .passed, "\(console.output)")
  }
}
