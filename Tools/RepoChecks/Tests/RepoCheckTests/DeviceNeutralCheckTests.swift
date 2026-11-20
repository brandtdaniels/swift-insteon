import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

// A made-up catalog: a relay with an alias and two flags, and a modem the libraries talk through.
private var defaultCatalog: [String: Any] {
  [
    "devices": [
      [
        "model": "9801", "name": "Garden Relay", "aliases": ["GardenLinc"],
        "capabilities": [["kind": "onOff"]], "commandSets": [["commandSet": "gardenRelay"]],
      ],
      [
        "model": "9899", "name": "Window Modem", "capabilities": [["kind": "modem"]],
        "commandSets": [["commandSet": "windowModem"]],
      ],
      ["model": "9898", "name": "Roof Hub", "capabilities": [["kind": "modem"], ["kind": "hub"]]],
    ],
    "commandSets": [
      ["id": "windowModem", "serialCommands": [["name": "readIdentity"]]],
      [
        "id": "gardenRelay",
        "operatingFlags": [
          ["name": "pulse", "label": "Pulse relay"],
          ["name": "pulseBoth"],
          ["name": "heartbeat", "label": "Heartbeat"],
        ],
        "extendedSettings": ["values": [["name": "pulseTime"], ["name": "onLevel"]]],
      ],
    ],
  ]
}

private let naming = """
  /// Links a Garden Relay 9801, or GardenLinc.
  let flag = "pulse"

  """

private let neutral = """
  /// Links a relay through the Window Modem and the Roof Hub, from its HEARTBEAT and onLevel.
  let flag = "pulseOn"
  let other = "repulse" + "pulseBothWays" + "98010"

  """

private let core = "Packages/InsteonCore/Sources/InsteonCore"

private struct Fixture {
  let directory = try! ScratchDirectory()
  var catalogURL: URL { directory.url(for: "catalog.json") }
  var allowlist: URL { directory.url(for: "allowlist.txt") }

  init(catalog: [String: Any] = defaultCatalog) {
    setCatalog(catalog)
  }

  func setCatalog(_ catalog: [String: Any]) {
    try! JSONSerialization.data(withJSONObject: catalog).write(to: catalogURL)
  }

  func write(_ relative: String, _ text: String) throws {
    try directory.write(text, to: relative)
  }

  func check(update: Bool = false) -> DeviceNeutralCheck {
    DeviceNeutralCheck(catalog: catalogURL, allowlist: allowlist, update: update)
  }

  func run(update: Bool = false) throws -> (status: CheckStatus, output: String) {
    let console = RecordingConsole()
    let status = try check(update: update).run(in: directory.url, console: console)
    return (status, console.output)
  }

  func violations() throws -> [DeviceNeutralViolation] {
    let words = try DeviceNeutralCheck.forbiddenWords(catalog: catalogURL)
    return try DeviceNeutralCheck.violations(in: directory.url, words: words)
  }
}

@Suite("check-device-neutral")
struct DeviceNeutralCheckTests {
  // test_takes_the_words_from_the_catalog
  @Test("takes the words from the catalog")
  func takesWordsFromCatalog() throws {
    let fixture = Fixture()
    let words = try DeviceNeutralCheck.forbiddenWords(catalog: fixture.catalogURL)

    #expect(
      Dictionary(uniqueKeysWithValues: words.map { ($0.key, $0.value.anyCase) }) == [
        // Product names and models, in their own case.
        "Garden Relay": false, "GardenLinc": false, "9801": false,
        // Command set ids, flag names and labels and setting names, in any case.
        "gardenRelay": true, "pulse": true, "Pulse relay": true, "pulseBoth": true,
        "pulseTime": true,
        "I/O Linc": true, "IOLinc": true, "IO Linc": true,
      ]
    )
  }

  // test_leaves_the_command_sets_of_a_modem_the_libraries_talk_through
  @Test("leaves the command sets of a modem the libraries talk through")
  func leavesModemCommandSets() throws {
    let fixture = Fixture()
    let words = try DeviceNeutralCheck.forbiddenWords(catalog: fixture.catalogURL)
    #expect(words["windowModem"] == nil)

    try fixture.write("\(core)/Modem.swift", "let id = \"windowModem\"\n")

    let (status, output) = try fixture.run()
    #expect(status == .passed, "\(output)")
  }

  // test_matches_identifiers_and_explicit_words_in_any_case
  @Test("matches identifiers and explicit words in any case")
  func matchesAnyCase() throws {
    let fixture = Fixture()
    try fixture.write(
      "\(core)/Relay.swift",
      "let set = \"GARDENRELAY\"\n// Turn its pulse relay flag off, and its PulseTime.\n// An iolinc, or an io linc.\n"
    )

    #expect(
      try fixture.violations().map { "\($0.word):\($0.line)" }
        == ["IO Linc:3", "IOLinc:3", "Pulse relay:2", "gardenRelay:1", "pulse:2", "pulseTime:2"]
    )
  }

  // test_finds_a_word_spelled_several_ways_once
  @Test("finds a word spelled several ways once")
  func findsWordSpelledSeveralWaysOnce() throws {
    let fixture = Fixture(catalog: [
      "devices": [
        ["model": "9802", "name": "Pond Relay", "aliases": ["PondLinc"], "capabilities": []]
      ],
      "commandSets": [["id": "pondLinc", "operatingFlags": [["name": "PONDLINC"]]]],
    ])
    try fixture.write("\(core)/Pond.swift", "// A pondlinc.\n")

    let words = try DeviceNeutralCheck.forbiddenWords(catalog: fixture.catalogURL)
    let found = try fixture.violations()

    #expect(words.keys.filter { $0.lowercased() == "pondlinc" }.count == 1)
    #expect(found.map { $0.word.lowercased() } == ["pondlinc"])
  }

  // test_finds_each_own_case_spelling_once_per_use
  @Test("finds each own-case spelling once per use")
  func findsOwnCaseSpellingOncePerUse() throws {
    let fixture = Fixture(catalog: [
      "devices": [
        [
          "model": "9803", "name": "Brook Bridge", "aliases": ["BrookBridge", "BROOKBRIDGE"],
          "capabilities": [],
        ]
      ],
      "commandSets": [],
    ])
    try fixture.write("\(core)/One.swift", "// A BrookBridge.\n")
    try fixture.write("\(core)/Other.swift", "// A brookbridge, then a BROOKBRIDGE.\n")
    try fixture.write("\(core)/Both.swift", "// A BrookBridge and a BROOKBRIDGE.\n")

    let words = try DeviceNeutralCheck.forbiddenWords(catalog: fixture.catalogURL)
    let found = try fixture.violations()

    #expect(words["BrookBridge"]?.anyCase == false)
    #expect(words["BrookBridge"]?.spellings == ["BROOKBRIDGE", "BrookBridge"])
    #expect(
      found.filter { $0.word == "BrookBridge" }.map {
        "\($0.path.split(separator: "/").last!):\($0.line)"
      } == ["Both.swift:1", "One.swift:1", "Other.swift:1"])
  }

  // test_matches_product_names_only_in_their_own_case
  @Test("matches product names only in their own case")
  func matchesProductNamesInOwnCase() throws {
    let fixture = Fixture()
    try fixture.write("\(core)/Relay.swift", "// Any garden relay, as plain words.\n")

    let (status, output) = try fixture.run()
    #expect(status == .passed, "\(output)")
  }

  // test_finds_each_word_once_per_file_by_its_first_line
  @Test("finds each word once per file by its first line")
  func findsEachWordOncePerFile() throws {
    let fixture = Fixture()
    try fixture.write("\(core)/Relay.swift", naming)

    #expect(
      try fixture.violations().map { "\($0.path) \($0.word) \($0.line)" } == [
        "\(core)/Relay.swift 9801 1", "\(core)/Relay.swift Garden Relay 1",
        "\(core)/Relay.swift GardenLinc 1",
        "\(core)/Relay.swift pulse 2",
      ]
    )
  }

  // test_matches_only_whole_words_and_leaves_modems_hubs_and_generic_words
  @Test("matches only whole words and leaves modems, hubs and generic words")
  func matchesWholeWords() throws {
    let fixture = Fixture()
    try fixture.write("Packages/InsteonCLI/Sources/insteon/Relay.swift", neutral)

    let (status, output) = try fixture.run()
    #expect(status == .passed, "\(output)")
  }

  // test_reads_tests_docs_and_the_in_memory_modem
  @Test("reads tests, docs and the in-memory modem")
  func readsTestsDocsAndModem() throws {
    let fixture = Fixture()
    try fixture.write(
      "Packages/InsteonCLI/Tests/InsteonCLISupportTests/RelayTests.swift", "let name = \"IOLinc\"\n"
    )
    try fixture.write("Packages/InsteonCore/README.md", "Link an I/O Linc.\n")
    try fixture.write(
      "Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport/InMemoryModem.swift",
      "// pulseBoth\n")

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(
      output.contains(
        "Packages/InsteonCLI/Tests/InsteonCLISupportTests/RelayTests.swift:1: names IOLinc"))
    #expect(output.contains("Packages/InsteonCore/README.md:1: names I/O Linc"))
    #expect(
      output.contains(
        "Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport/InMemoryModem.swift:1: names pulseBoth"
      ))
  }

  // test_leaves_other_packages_alone
  @Test("leaves other packages alone")
  func leavesOtherPackages() throws {
    let fixture = Fixture()
    try fixture.write(
      "Packages/InsteonDeviceCatalog/Tests/InsteonDeviceCatalogTests/BundledTests.swift", naming)
    try fixture.write("Packages/InsteonTestSupport/Sources/InsteonTestSupport/Clock.swift", naming)

    let (status, output) = try fixture.run()
    #expect(status == .passed, "\(output)")
  }

  // test_allows_a_listed_file_and_word_and_fails_a_stale_entry
  @Test("allows a listed file and word and fails a stale entry")
  func allowsListedFailsStale() throws {
    let fixture = Fixture()
    try fixture.write("\(core)/Relay.swift", "let flag = \"pulse\"\n")
    try fixture.write(
      "allowlist.txt", "# Known.\n\(core)/Relay.swift\tpulse\tWaiting to move to the catalog.\n")

    var (status, output) = try fixture.run()
    #expect(status == .passed, "\(output)")
    #expect(output.contains("1 known"))

    try fixture.write("\(core)/Relay.swift", "let flag = \"other\"\n")

    (status, output) = try fixture.run()
    #expect(status == .failed)
    #expect(output.contains("no longer found, so remove it: \(core)/Relay.swift\tpulse"))
  }

  // test_refuses_an_entry_without_a_reason
  @Test("refuses an entry without a reason")
  func refusesEntryWithoutReason() throws {
    let fixture = Fixture()
    try fixture.write("allowlist.txt", "\(core)/Relay.swift\tpulse\n")

    #expect(throws: CheckFailure.self) { try fixture.run() }
  }

  // test_writes_the_allowlist_keeping_reasons
  @Test("writes the allow-list keeping reasons")
  func writesAllowlistKeepingReasons() throws {
    let fixture = Fixture()
    try fixture.write("\(core)/Relay.swift", naming)
    try fixture.write("allowlist.txt", "\(core)/Relay.swift\tpulse\tA reason.\n")

    #expect(try fixture.run(update: true).status == .passed)

    let entries = try String(contentsOf: fixture.allowlist, encoding: .utf8).split(separator: "\n")
      .filter { !$0.hasPrefix("#") }.map(String.init)
    #expect(entries.contains("\(core)/Relay.swift\tpulse\tA reason."))
    #expect(entries.contains("\(core)/Relay.swift\tGardenLinc\t"))
    #expect(entries.count == 4)
  }

  @Test("prints each finding with its advice, and the success line with the known count")
  func messages() throws {
    let fixture = Fixture()
    try fixture.write("\(core)/Relay.swift", "let flag = \"pulse\"\n")

    #expect(
      try fixture.run().output == """
        \(core)/Relay.swift:1: names pulse, a real product or operating flag
          Instead, take it from the catalog, or use an invented name in a test's own catalog.

        """
    )

    try fixture.write("\(core)/Relay.swift", "let flag = 1\n")
    #expect(
      try fixture.run().output
        == "No real product or operating flag named (0 known, in allowlist.txt).\n")
  }

  @Test("skips a file that isn't UTF-8 and reads one with a byte order mark")
  func skipsUndecodableFiles() throws {
    let fixture = Fixture()
    try fixture.directory.write(
      Data([0xFF, 0x70, 0x75, 0x6C, 0x73, 0x65]), to: "\(core)/Binary.dat")
    try fixture.directory.write(
      Data([0xEF, 0xBB, 0xBF]) + Data("pulse\n".utf8), to: "\(core)/Bom.txt")

    #expect(try fixture.violations().map(\.path) == ["\(core)/Bom.txt"])
  }

  // test_the_repository_passes
  @Test("passes on this repository")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let console = RecordingConsole()

    #expect(
      try DeviceNeutralCheck().run(in: root, console: console) == .passed, "\(console.output)")
  }
}

@Suite("check-device-neutral catalog file")
struct DeviceNeutralCatalogFileTests {
  private func run(catalog: Data) throws -> CheckStatus {
    let fixture = Fixture()
    try catalog.write(to: fixture.catalogURL)
    return try fixture.check().run(in: fixture.directory.url, console: RecordingConsole())
  }

  @Test("refuses a catalog that isn't valid JSON, in the forms Python's json.loads refuses")
  func refusesInvalidJSON() throws {
    let valid = try JSONSerialization.data(withJSONObject: defaultCatalog)
    let bom = Data([0xEF, 0xBB, 0xBF]) + valid
    let trailingComma = Data(#"{"devices": [],"commandSets": [],}"#.utf8)

    for bytes in [bom, trailingComma, Data(#"{"a": [1,2,],"b":1}"#.utf8), Data(), Data(#"{"devices": ["#.utf8)] {
      #expect(throws: CheckFailure.self) { try run(catalog: bytes) }
    }
  }

  @Test("names the file and keeps to one line in the message")
  func namesFile() throws {
    do {
      _ = try run(catalog: Data("[1,]".utf8))
      Issue.record("expected a failure")
    } catch let failure as CheckFailure {
      #expect(failure.message.contains("catalog.json: isn't valid JSON"))
      #expect(!failure.message.contains("\n"))
    }
  }

  @Test("refuses JSON that isn't an object, and passes an object that holds no catalog, as the script did")
  func objectOnly() throws {
    #expect(throws: CheckFailure.self) { try run(catalog: Data("[]".utf8)) }
    #expect(try run(catalog: Data("{}".utf8)) == .passed)
  }
}
