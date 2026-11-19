import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

/// A git that answers from dictionaries.
private struct StubGit: GitReading {
  var base: [String: String] = [:]
  var diffs: [String: String] = [:]

  func fileExists(ref: String, path: String) -> Bool { base[path] != nil }
  func show(ref: String, path: String) throws -> String { base[path] ?? "" }
  func diff(ref: String, path: String) throws -> String { diffs[path] ?? "" }
}

private let cliThin = "Scripts/check-cli-thin-allowlist.txt"
private let concurrency = "Scripts/check-concurrency-allowlist.txt"
private let credentials = "Scripts/check-credentials-allowlist.txt"
private let deviceNeutral = "Scripts/check-device-neutral-allowlist.txt"

private struct Fixture {
  let directory = try! ScratchDirectory()
  var git = StubGit()

  /// Every list at the base and in the working tree, with the same text.
  init(base: [String: String] = [:], head: [String: String] = [:]) {
    git.base = base
    for (path, text) in head {
      try! directory.write(text, to: path)
    }
  }

  func run() throws -> (status: CheckStatus, output: String) {
    let console = RecordingConsole()
    let status = try AllowListGrowthCheck(base: "origin/main", git: git).run(in: directory.url, console: console)
    return (status, console.output)
  }
}

@Suite("allowlist-growth")
struct AllowListGrowthCheckTests {
  @Test("says there's nothing to compare for a list the base doesn't have")
  func baseWithoutList() throws {
    let output = try Fixture().run().output

    #expect(
      output == String(
        repeating: "The base branch has no allow-list yet, so there's nothing to compare.\n",
        count: 4
      )
    )
  }

  @Test("passes when no list grew")
  func noGrowth() throws {
    let text = "# header\nentry\tone\tcode\treason\n"
    var fixture = Fixture(base: [concurrency: text, credentials: text, deviceNeutral: text], head: [concurrency: text, credentials: text, deviceNeutral: text])
    fixture.git.base[cliThin] = ""

    let (status, output) = try fixture.run()

    #expect(status == .passed)
    #expect(output == String(repeating: "The allow-list didn't grow.\n", count: 4))
  }

  @Test("fails on a line added to the cli-thin list, other than a comment or a diff header")
  func cliThinGrowth() throws {
    var fixture = Fixture()
    fixture.git.base[cliThin] = ""
    fixture.git.diffs[cliThin] = "--- a/x\n+++ b/x\n@@ -1,0 +2 @@\n+# comment\n+insteon/A.swift\tengine\tx\n+\n"

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(
      output.hasPrefix(
        "These lines were added to \(cliThin), which may only lose lines:\n+insteon/A.swift\tengine\tx\nMove the code into the libraries instead of allowing it.\n"
      )
    )
  }

  @Test("compares entries by their key columns and counts a repeated entry")
  func entriesByKey() throws {
    let base = "# header\na\tb\tc\treason\nd\te\tf\tr\n"
    let head = "# header\na\tb\tc\tnew reason\nd\te\tf\tr\nd\te\tf\tr\nx\ty\tz\tr\n"
    let fixture = Fixture(base: [concurrency: base], head: [concurrency: head])

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(
      output.contains(
        "These entries were added to \(concurrency), which may only lose entries:\nd\te\tf\nx\ty\tz\nKeep the work structured and the clock injected instead of allowing it.\n"
      )
    )
  }

  @Test("lets a list lose entries and have its reasons reworded")
  func shrinkAndReword() throws {
    let base = "a\tb\tc\told\nd\te\tf\tr\n"
    let head = "a\tb\tc\tworded again\n"
    let (status, output) = try Fixture(base: [credentials: base], head: [credentials: head]).run()

    #expect(status == .passed)
    #expect(output.contains("The allow-list didn't grow."))
  }

  @Test("gives each list its own advice")
  func advice() throws {
    let head = "n\tw\tr\n"
    let fixture = Fixture(base: [credentials: "", deviceNeutral: ""], head: [credentials: head, deviceNeutral: head])

    let output = try fixture.run().output

    #expect(output.contains("Leave the credential out of the string instead of allowing it.\n"))
    #expect(output.contains("Take the name from the catalog, or use an invented one, instead of allowing it.\n"))
  }
}
