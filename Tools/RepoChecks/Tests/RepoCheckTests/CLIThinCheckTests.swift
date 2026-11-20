import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

// A command that decides what a device does, once by each rule.
private let thick = """
  enum DeviceCommands {
    static func on(_ known: DeviceDescription?) async throws {
      if known?.category == .dimmableLightingControl { print("dims") }
      if known?.firmwareVersion ?? 0 >= 0x41 { print("new firmware") }
      if kind == .relay { print("on/off only") }
      if engine == .i2cs { print("checksum") }
      try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.beep))
    }
  }

  """

// A command that only words what the library says, with the rules' words in comments and strings.
private let thin = #"""
  // A relay, category 0x02, is on/off only: kind == .relay.
  /* firmwareVersion >= 0x41 */
  enum DeviceCommands {
    static func on(_ device: Device) async throws {
      let result = try await device.turnOn(level: 50)
      print("category == 0x01 or StandardDirectCommand.on")
      print("""
        kind == .relay
        """)
      print("Turned \(result.group) on.")
    }
  }

  """#

private struct Fixture {
  let directory = try! ScratchDirectory()
  var root: URL { directory.url(for: "insteon") }
  var allowlist: URL { directory.url(for: "allowlist.txt") }

  init() {
    try! directory.makeDirectory("insteon")
  }

  func write(_ name: String, _ text: String) throws {
    try directory.write(text, to: "insteon/\(name)")
  }

  func run(_ extra: [String] = [], roots: [URL]? = nil) throws -> (status: CheckStatus, output: String) {
    let console = RecordingConsole()
    let status = try CLIThinCheck(sources: roots ?? [root], allowlist: allowlist, update: extra.contains("--update"))
      .run(in: directory.url, console: console)
    return (status, console.output)
  }

  func rules() throws -> [String] {
    Array(Set(try CLIThinCheck.violations(in: [root]).map(\.rule))).sorted()
  }

  func rules(of code: String) throws -> [String] {
    try write("DeviceCommands.swift", code)
    return try rules()
  }
}

@Suite("check-cli-thin")
struct CLIThinCheckTests {
  // test_finds_each_rule
  @Test("finds each rule")
  func findsEachRule() throws {
    let fixture = Fixture()
    try fixture.write("DeviceCommands.swift", thick)

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(try fixture.rules() == ["category", "engine", "firmware", "group-kind", "hex-literal", "protocol-command"])
    #expect(output.contains("DeviceCommands.swift:3: category:"))
  }

  // test_ignores_comments_and_strings
  @Test("ignores comments and strings")
  func ignoresCommentsAndStrings() throws {
    let fixture = Fixture()
    try fixture.write("DeviceCommands.swift", thin)

    let (status, output) = try fixture.run()

    #expect(status == .passed, "\(output)")
    #expect(try fixture.rules() == [])
  }

  // test_reads_interpolations_as_code
  @Test("reads interpolations as code")
  func readsInterpolations() throws {
    #expect(try Fixture().rules(of: "print(\"is \\(kind == .relay ? \"on\" : \"off\")\")\n") == ["group-kind"])
  }

  // test_waives_bytes_and_commands_only_for_the_raw_passthroughs
  @Test("waives bytes and commands only for the raw passthroughs")
  func waivesForPassthroughs() throws {
    let fixture = Fixture()
    try fixture.write("ExploreCommands.swift", thick)

    #expect(try fixture.rules() == ["category", "engine", "firmware", "group-kind"])
  }

  // test_passes_known_lines_and_fails_new_ones
  @Test("passes known lines and fails new ones")
  func passesKnownFailsNew() throws {
    let fixture = Fixture()
    try fixture.write("DeviceCommands.swift", thick)

    #expect(try fixture.run(["--update"]).status == .passed)
    let known = try fixture.run()
    #expect(known.status == .passed, "\(known.output)")

    try fixture.write("SceneCommands.swift", "let command = StandardDirectCommand.on(level: 0xFF)\n")

    let (status, output) = try fixture.run()
    #expect(status == .failed)
    #expect(output.contains("SceneCommands.swift:1: hex-literal:"))
    #expect(output.contains("SceneCommands.swift:1: protocol-command:"))
    #expect(!output.contains("DeviceCommands.swift"))
  }

  // test_fails_on_an_entry_that_no_longer_matches
  @Test("fails on an entry that no longer matches")
  func failsOnStaleEntry() throws {
    let fixture = Fixture()
    try fixture.write("DeviceCommands.swift", thick)
    _ = try fixture.run(["--update"])
    try fixture.write("DeviceCommands.swift", thin)

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("no longer found, so remove it"))
  }

  // test_counts_a_repeated_line_once_for_each_entry
  @Test("counts a repeated line once for each entry")
  func countsRepeatedLine() throws {
    let fixture = Fixture()
    let line = "if kind == .relay { print() }\n"
    try fixture.write("DeviceCommands.swift", line)
    _ = try fixture.run(["--update"])
    try fixture.write("DeviceCommands.swift", line + line)

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("DeviceCommands.swift:2: group-kind:"))
  }

  // test_finds_raw_value_comparisons
  @Test("finds raw value comparisons")
  func findsRawValueComparisons() throws {
    let fixture = Fixture()
    #expect(try fixture.rules(of: "if known.category.rawValue == 1 { }\n") == ["category"])
    #expect(try fixture.rules(of: "if identity.subcategory?.rawValue != 2 { }\n") == ["category"])
    #expect(try fixture.rules(of: "if group.kind.rawValue == \"relay\" { }\n") == ["group-kind"])
    #expect(try fixture.rules(of: "if identity.firmwareVersion.rawValue >= 65 { }\n") == ["firmware"])
  }

  // test_finds_decimal_command_bytes
  @Test("finds decimal command bytes")
  func findsDecimalCommandBytes() throws {
    let fixture = Fixture()
    #expect(try fixture.rules(of: "let command = Command(command1: 17, command2: 255)\n") == ["command-byte"])
    #expect(try fixture.rules(of: "let command = Command(command1: received.command1, command2: level)\n") == [])
  }

  // test_waives_decimal_command_bytes_for_the_raw_passthroughs
  @Test("waives decimal command bytes for the raw passthroughs")
  func waivesDecimalBytes() throws {
    let fixture = Fixture()
    try fixture.write("ExploreCommands.swift", "let command = Command(command1: 17, command2: 0)\n")

    #expect(try fixture.rules() == [])
  }

  // test_finds_a_kind_among_kinds
  @Test("finds a kind among kinds")
  func findsKindAmongKinds() throws {
    let fixture = Fixture()
    #expect(try fixture.rules(of: "if [.dimmer, .relay].contains(kind) { }\n") == ["group-kind"])
    #expect(try fixture.rules(of: "if onOffKinds.contains(group.kind) { }\n") == ["group-kind"])
  }

  // test_allows_comparisons_with_nil
  @Test("allows comparisons with nil")
  func allowsNilComparisons() throws {
    let fixture = Fixture()
    #expect(try fixture.rules(of: "if category != nil, names.catalog != nil { }\n") == [])
    #expect(try fixture.rules(of: "if rows.contains(where: { $0.category == nil }) { }\n") == [])
    #expect(try fixture.rules(of: "if nil == known?.firmwareVersion { }\n") == [])
  }

  // test_ignores_raw_strings
  @Test("ignores raw strings")
  func ignoresRawStrings() throws {
    let fixture = Fixture()
    #expect(try fixture.rules(of: "print(#\"He said \"kind == .relay\" and \\(0x01)\"#)\n") == [])
    #expect(try fixture.rules(of: "print(##\"a \"# kind == .relay\"##)\n") == [])
    #expect(try fixture.rules(of: "print(#\"\"\"\n  kind == .relay \"quoted\"\n  \"\"\"#)\n") == [])
  }

  // test_reads_a_raw_strings_interpolations_as_code
  @Test("reads a raw string's interpolations as code")
  func readsRawInterpolations() throws {
    #expect(try Fixture().rules(of: "print(#\"is \\#(kind == .relay ? \"on\" : \"off\")\"#)\n") == ["group-kind"])
  }

  // test_ignores_nested_block_comments
  @Test("ignores nested block comments")
  func ignoresNestedBlockComments() throws {
    let code = "/* outer /* inner */ kind == .relay\n still a comment: 0x01 */\nlet thin = true\n"

    #expect(try Fixture().rules(of: code) == [])
  }

  // test_reads_code_after_a_nested_block_comment
  @Test("reads code after a nested block comment")
  func readsCodeAfterNestedComment() throws {
    #expect(try Fixture().rules(of: "/* a /* b */ c */ if kind == .relay { }\n") == ["group-kind"])
  }

  // test_checks_every_root_by_its_path_from_the_roots_parent
  @Test("checks every root by its path from the root's parent")
  func checksEveryRoot() throws {
    let fixture = Fixture()
    try fixture.directory.write("let level = 0xFF\n", to: "InsteonCLISupport/ControlText.swift")
    try fixture.write("DeviceCommands.swift", "if kind == .relay { }\n")

    let (status, output) = try fixture.run(roots: [fixture.root, fixture.directory.url(for: "InsteonCLISupport")])

    #expect(status == .failed)
    #expect(output.contains("insteon/DeviceCommands.swift:1: group-kind:"))
    #expect(output.contains("InsteonCLISupport/ControlText.swift:1: hex-literal:"))
  }

  @Test("refuses a malformed allow-list line with the script's message")
  func refusesMalformedAllowlist() throws {
    let fixture = Fixture()
    try fixture.directory.write("# header\nonly\ttwo\n", to: "allowlist.txt")

    #expect(throws: CheckFailure.self) { try fixture.run() }
    do {
      _ = try fixture.run()
    } catch let failure as CheckFailure {
      #expect(failure.message == "\(fixture.allowlist.path): not an entry, which is a path, a rule and code separated by tabs: only\ttwo")
    }
  }

  @Test("writes the allow-list with its header and says how many lines")
  func writesAllowlist() throws {
    let fixture = Fixture()
    try fixture.write("DeviceCommands.swift", "if kind == .relay {  }\n")

    let (_, output) = try fixture.run(["--update"])

    #expect(output == "Wrote 1 known lines to \(fixture.allowlist.path).\n")
    let written = try String(contentsOf: fixture.allowlist, encoding: .utf8)
    #expect(written.hasSuffix("insteon/DeviceCommands.swift\tgroup-kind\tif kind == .relay { }\n"))
  }

  @Test("prints the success line with the known count")
  func printsSuccess() throws {
    let fixture = Fixture()
    try fixture.write("DeviceCommands.swift", thin)

    #expect(try fixture.run().output == "The insteon command stays thin: no new lines break the rules (0 known, in allowlist.txt).\n")
  }

  @Test("passes on this repository")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let console = RecordingConsole()

    #expect(try CLIThinCheck().run(in: root, console: console) == .passed, "\(console.output)")
  }
}

@Suite("SwiftCodeScanner")
struct SwiftCodeScannerTests {
  @Test("turns a string into quotes followed by its interpolations' code")
  func stringsAndInterpolations() {
    let lines = SwiftCodeScanner.lines(in: "let a = \"x \\(f(1)) y\" // note\n")

    #expect(lines[0].code == "let a = \"\"f(1)  ")
    #expect(lines[0].interpolations == ["f(1))"])
    #expect(!lines[0].hasUnclosedInterpolation)
  }

  @Test("records an interpolation that doesn't close on its line")
  func unclosed() {
    let lines = SwiftCodeScanner.lines(in: "let a = \"x \\(f(\n1)\"\n")

    #expect(lines[0].hasUnclosedInterpolation)
    #expect(lines[0].interpolations == ["f("])
  }

  @Test("reads a nested interpolation before the one around it")
  func nestedInterpolation() {
    let lines = SwiftCodeScanner.lines(in: "\"\\(a(\"\\(b)\"))\"\n")

    #expect(lines[0].interpolations == ["b)", "a(\"\\(b)\"))"])
  }

  @Test("reads a CRLF file as lines and keeps a combining mark with its scalar")
  func newlinesAndMarks() {
    let lines = SwiftCodeScanner.lines(in: TextFile.normalizingNewlines("a\r\nb\u{301}\r\n"))

    #expect(lines.map(\.code) == ["a", "b\u{301}", ""])
  }

  @Test("carries a block comment and a multiline string across lines")
  func acrossLines() {
    let lines = SwiftCodeScanner.lines(in: "a /* x\ny */ b\nc \"\"\"\nz\n\"\"\" d\n")

    #expect(lines.map(\.code) == ["a ", " b", "c ", "", "\"\" d", ""])
  }
}
