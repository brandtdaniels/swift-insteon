import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

// Credentials written into strings, one per line, several ways.
private let leaky = ##"""
  struct Login {
    func lines(user: String, password: String, hub: Hub) -> [String] {
      let header = "Basic \(user):\(password)"
      print("Signing in with \(hub.password)")
      let raw = #"token=\#(apiToken)"#
      let note = """
        Header: \(authorizationHeader)
        """
      return ["\(Secrets.clientSecret.uppercased())", "\("nested \(bearerToken)")"]
    }
  }

  """##

// The same words where no credential is interpolated: in plain text, comments, and names
// that aren't interpolated.
private let clean = ##"""
  // print("\(password)") in a comment.
  /* "\(token)" in a block comment. */
  struct Login {
    func lines(user: String, password: String) -> [String] {
      let message = "The Hub's user name and password go in the environment."
      let header = makeHeader(user: user, password: password)
      let raw = #"\(password) isn't an interpolation in a raw string"#
      return ["\(user) signed in", message, header, raw]
    }
  }

  """##

private struct Fixture {
  let directory = try! ScratchDirectory()
  var packages: URL { directory.url(for: "Packages") }
  var allowlist: URL { directory.url(for: "allowlist.txt") }

  func write(_ relative: String, _ source: String) throws {
    try directory.write(source, to: "Packages/\(relative)")
  }

  func run(update: Bool = false) throws -> (status: CheckStatus, output: String) {
    let console = RecordingConsole()
    let status = try CredentialsCheck(packages: packages, allowlist: allowlist, update: update).run(in: directory.url, console: console)
    return (status, console.output)
  }

  func violations() throws -> [String] {
    try CredentialsCheck.violations(in: packages).map { "\($0.names):\($0.line)" }
  }
}

@Suite("check-credentials")
struct CredentialsCheckTests {
  // test_finds_each_interpolated_credential
  @Test("finds each interpolated credential")
  func findsEach() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Login.swift", leaky)

    #expect(
      try fixture.violations() == [
        "password:3", "password:4", "apiToken:5", "authorizationHeader:7", "Secrets,bearerToken,clientSecret:9"
      ]
    )
  }

  // test_ignores_plain_text_comments_and_names_outside_interpolations
  @Test("ignores plain text, comments and names outside interpolations")
  func ignoresClean() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Login.swift", clean)

    #expect(try fixture.violations() == [])
  }

  // test_reads_the_command_but_not_tests
  @Test("reads the command but not tests")
  func readsCommandNotTests() throws {
    let fixture = Fixture()
    try fixture.write("InsteonCLI/Sources/insteon/Login.swift", "let line = \"\\(password)\"\n")
    try fixture.write("Lib/Tests/LibTests/LoginTests.swift", "let line = \"\\(password)\"\n")

    #expect(try CredentialsCheck.violations(in: fixture.packages).map(\.path) == ["InsteonCLI/Sources/insteon/Login.swift"])
  }

  // test_passes_with_every_line_allowed_and_fails_on_a_new_one
  @Test("passes with every line allowed and fails on a new one")
  func passesAllowedFailsNew() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Auth.swift", "let header = \"\\(user):\\(password)\"\n")
    try fixture.directory.write("# Known.\nLib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.\n", to: "allowlist.txt")

    #expect(try fixture.run().status == .passed)

    try fixture.write("Lib/Sources/Lib/Log.swift", "print(\"\\(token)\")\n")
    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("Lib/Sources/Lib/Log.swift:1: interpolates token"))
  }

  // test_fails_on_an_entry_that_no_longer_matches
  @Test("fails on an entry that no longer matches")
  func failsOnStaleEntry() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Auth.swift", "let header = makeHeader()\n")
    try fixture.directory.write("Lib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.\n", to: "allowlist.txt")

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("no longer found, so remove it"))
  }

  // test_refuses_an_entry_without_a_reason
  @Test("refuses an entry without a reason")
  func refusesEntryWithoutReason() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Auth.swift", "let header = \"\\(password)\"\n")
    try fixture.directory.write("Lib/Sources/Lib/Auth.swift\tpassword\t\n", to: "allowlist.txt")

    #expect(throws: CheckFailure.self) { try fixture.run() }
  }

  // test_update_keeps_the_reasons_of_entries_that_remain
  @Test("update keeps the reasons of entries that remain")
  func updateKeepsReasons() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Auth.swift", "let header = \"\\(password)\"\nprint(\"\\(token)\")\n")
    try fixture.directory.write("Lib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.\n", to: "allowlist.txt")

    #expect(try fixture.run(update: true).status == .passed)

    let entries = try String(contentsOf: fixture.allowlist, encoding: .utf8).split(separator: "\n")
      .filter { !$0.hasPrefix("#") }.map(String.init)
    #expect(entries == ["Lib/Sources/Lib/Auth.swift\tpassword\tBuilds the header.", "Lib/Sources/Lib/Auth.swift\ttoken\t"])
  }

  // test_reads_names_as_words
  @Test("reads names as words")
  func readsNamesAsWords() {
    let matching = [
      "password", "hubPassword", "passwordPrompt", "INSTEON_PASSWORD", "passwd", "pwd", "userPwd",
      "passphrase", "token", "accessTokens", "bearerToken", "secret", "clientSecrets", "credential",
      "credentials", "creds", "authorization", "authorizationHeader", "bearer", "apiKey", "APIKey",
      "api_key", "apikey", "privateKey", "accessKey", "PRIVATE_KEY"
    ]
    let other = ["tokenizer", "detokenize", "passage", "secretary", "keyPath", "privateMode", "accessLevel", "user", "host"]

    #expect(matching.filter { !CredentialsCheck.isCredential($0) } == [])
    #expect(other.filter { CredentialsCheck.isCredential($0) } == [])
  }

  // test_reads_string_literals_inside_an_interpolation
  @Test("reads string literals inside an interpolation")
  func readsStringsInsideInterpolation() throws {
    let fixture = Fixture()
    try fixture.write(
      "Lib/Sources/Lib/Env.swift",
      #"""
      let a = "Hub \(environment["INSTEON_PASSWORD"] ?? "")"
      let b = "Hub \(environment["INSTEON_HUB_HOST"] ?? "")"
      let c = "INSTEON_PASSWORD isn't set, so \(name) can't sign in."

      """#
    )

    #expect(try fixture.violations() == ["INSTEON_PASSWORD:1"])
  }

  // test_fails_on_an_interpolation_not_closed_on_its_line
  @Test("fails on an interpolation not closed on its line")
  func failsOnUnclosed() throws {
    let fixture = Fixture()
    try fixture.write(
      "Lib/Sources/Lib/Long.swift",
      #"""
      let text = """
        Signed in as \(account.name(
          for: hub
        ))
        """

      """#
    )
    try fixture.directory.write("", to: "allowlist.txt")

    let (status, output) = try fixture.run()

    #expect(status == .failed)
    #expect(output.contains("Lib/Sources/Lib/Long.swift:2: an interpolation isn't closed on its line"))

    // An update doesn't allow it.
    _ = try fixture.run(update: true)

    #expect(try fixture.run().status == .failed)
  }

  @Test("prints the success line with the known count and the advice with each finding")
  func messages() throws {
    let fixture = Fixture()
    try fixture.write("Lib/Sources/Lib/Log.swift", "print(\"\\(token)\")\n")

    #expect(
      try fixture.run().output == """
        Lib/Sources/Lib/Log.swift:1: interpolates token
          Instead, leave the credential out of the string, such as by naming what it's for.

        """
    )

    try fixture.write("Lib/Sources/Lib/Log.swift", "print(1)\n")
    #expect(try fixture.run().output == "No credentials interpolated into strings (0 known, in allowlist.txt).\n")
  }

  @Test("passes on this repository")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let console = RecordingConsole()

    #expect(try CredentialsCheck().run(in: root, console: console) == .passed, "\(console.output)")
  }
}
