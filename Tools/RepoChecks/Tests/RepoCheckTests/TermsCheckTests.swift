import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

/// The forms the rules find in a line of prose, in the order of the rules.
private func ruledOut(_ text: String) -> [String] {
  TermsCheck.rules.compactMap { PythonPattern(python: $0.pattern).search(text)?.text }
}

@Suite("check-terms rules")
struct TermsRulesTests {
  // test_finds_each_ruled_out_form
  @Test("finds each ruled-out form")
  func findsEachForm() {
    #expect(ruledOut("INSTEON devices") == ["INSTEON"])
    #expect(ruledOut("an I2CS device") == ["I2CS"])
    #expect(ruledOut("an acknowledgement") == ["acknowledgement"])
    #expect(ruledOut("over the power line") == ["power line"])
    #expect(ruledOut("its on level") == ["on level"])
    #expect(ruledOut("the 2242 Hub") == ["2242 Hub"])
    #expect(ruledOut("the PowerLinc Modem (2413U)") == ["Modem (2413U)"])
    #expect(ruledOut("an All-Link group") == ["All-Link"])
    #expect(ruledOut("the link database") == ["link database"])
    #expect(ruledOut("the clean-up") == ["clean-up"])
    #expect(ruledOut("press the Set button") == ["Set button"])
    #expect(ruledOut("as the guide says") == ["the guide"])
    #expect(ruledOut("a home backup") == ["home backup"])
    #expect(ruledOut("the home name") == ["home name"])
    #expect(ruledOut("the home's scenes") == ["home's scenes"])
    #expect(ruledOut("the home's modem") == ["home's modem"])
    #expect(ruledOut("in the home's time zone") == ["home's time"])
    #expect(ruledOut("the home's place") == ["home's place"])
    #expect(ruledOut("a home's rules") == ["home's rules"])
  }

  // test_accepts_the_forms_to_use
  @Test("accepts the forms to use")
  func acceptsFormsToUse() {
    for text in [
      "Insteon devices, i2CS, an acknowledgment, the powerline, its on-level",
      "the Hub 2242, the PowerLinc Modem 2413U, an ALL-Link group, the ALL-Link database",
      "ALL-Link cleanup, the SET button, the Insteon Developer's Guide (2009)",
      "the network backup, the network name, the network's scenes, the network's time zone, the home's two power phases, the home's wiring, a home directory"
    ] {
      #expect(ruledOut(text) == [], "\(text)")
    }
  }

  // test_finds_temporal_wording
  @Test("finds temporal wording")
  func findsTemporalWording() {
    #expect(ruledOut("It currently reads the database.") == ["currently"])
    #expect(ruledOut("Previously it read the database.") == ["Previously"])
    #expect(ruledOut("The registry no longer has it.") == ["no longer"])
    #expect(ruledOut("The modem now answers.") == ["now"])
    #expect(ruledOut("Now press the SET button.") == ["Now"])
    #expect(ruledOut("A new option, --force, sends it.") == ["new option"])
    #expect(ruledOut("The newly added flag.") == ["newly"])
  }

  // test_accepts_wording_that_isnt_temporal
  @Test("accepts wording that isn't temporal")
  func acceptsNonTemporalWording() {
    for text in [
      "///   - now: The time to record, for when a device last answered.",
      "The modem reports a new link, and the buffer holds new bytes.",
      "Each call returns a new stream; the record becomes the new end.",
      "It knows the device's current state, and the record isn't in use.",
      "A snowy nowhere, a knowledgeable reader."
    ] {
      #expect(ruledOut(text) == [], "\(text)")
    }
  }

  @Test("reads a word boundary by Python's word characters, not ICU's")
  func boundaryIsPythonsWord() {
    #expect(ruledOut("\u{E9}INSTEON") == [])
    #expect(ruledOut("e\u{301}INSTEON") == ["INSTEON"])
    #expect(ruledOut("INSTEON_x") == [])
  }
}

@Suite("check-terms prose")
struct TermsProseTests {
  private func prose(_ text: String, isMarkdown: Bool) -> [(Int, String)] {
    TermsCheck().prose(in: text, isMarkdown: isMarkdown)
      .map { ($0.number, PythonText.strip($0.text)) }
      .filter { !$0.1.isEmpty }
  }

  // test_reads_swift_comments_and_not_code_or_strings
  @Test("reads Swift comments and not code or strings")
  func readsSwiftComments() {
    let source = #"""
      /// Reads the `INSTEON` database.
      let now = "currently"  // It currently waits.
      let lines = """
        no longer
        """
      /// ```swift
      /// let now = Date()
      /// ```

      """#

    let found = prose(source, isMarkdown: false)

    #expect(found.map(\.0) == [1, 2])
    #expect(found.map(\.1) == ["/// Reads the  database.", "// It currently waits."])
  }

  // test_reads_markdown_and_not_code
  @Test("reads Markdown and not code")
  func readsMarkdown() {
    let markdown = """
      The modem `now` answers.

      ```text
      insteon --now
      ```

          indented code, no longer read
      - A list item that's read.

      """

    let found = prose(markdown, isMarkdown: true)

    #expect(found.map(\.0) == [1, 8])
    #expect(found.map(\.1) == ["The modem  answers.", "- A list item that's read."])
  }
}

@Suite("check-terms report")
struct TermsReportTests {
  @Test("reports each rule once per line, in path, line and rule order, with Python's repr")
  func reports() throws {
    let directory = try ScratchDirectory()
    try directory.write("The Developer's guide, now.\n", to: "b.md")
    try directory.write("a\n// INSTEON now\n", to: "a/z.swift")
    try directory.write("INSTEON\n", to: "a.md")
    try directory.write("INSTEON\n", to: "CONVENTIONS.md")
    try directory.write("INSTEON\n", to: ".build/x.md")
    try directory.write("INSTEON\n", to: "notes.txt")

    let found = try TermsCheck().problems(in: directory.url)

    #expect(
      found == [
        "a/z.swift:2: 'INSTEON': use Insteon",
        "a/z.swift:2: 'now': use what's true, without a time",
        "a.md:1: 'INSTEON': use Insteon",
        "b.md:1: \"Developer's guide\": use the document's title, such as Insteon Developer's Guide",
        "b.md:1: 'now': use what's true, without a time"
      ]
    )
  }

  @Test("ends with status 1 on a finding and prints the success line otherwise")
  func status() throws {
    let directory = try ScratchDirectory()
    try directory.write("Fine.\n", to: "a.md")
    let console = RecordingConsole()

    #expect(try TermsCheck().run(in: directory.url, console: console) == .passed)
    #expect(console.lines == ["No ruled-out terms."])

    try directory.write("INSTEON\n", to: "a.md")
    #expect(try TermsCheck().run(in: directory.url, console: RecordingConsole()) == .failed)
  }

  @Test("reads a CRLF file and counts its lines")
  func crlf() throws {
    let directory = try ScratchDirectory()
    try directory.write("ok\r\nINSTEON\r\n", to: "a.md")

    #expect(try TermsCheck().problems(in: directory.url) == ["a.md:2: 'INSTEON': use Insteon"])
  }

  @Test("passes on this repository")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    #expect(try TermsCheck().problems(in: root) == [])
  }
}
