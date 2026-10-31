#if os(macOS) || os(Linux)
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing
import InsteonCLISupport

/// Reading the environment file from a temporary directory, with the permissions each test
/// gives it. The files hold made-up values, never a real Hub's.
struct EnvironmentFileReadingTests {

  let directory: String = NSTemporaryDirectory() + "insteon-env-tests-" + UUID().uuidString

  let contents = "INSTEON_HUB_USER=example\nINSTEON_HUB_PASSWORD=not-a-real-password\n"

  /// Writes a file in the test's directory with permissions, and returns its path.
  func file(named name: String = "env", containing text: String? = nil, permissions: Int) throws -> String {

    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    let path: String = directory + "/" + name

    #expect(FileManager.default.createFile(atPath: path, contents: Data((text ?? contents).utf8)))
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)

    return path

  }

  func removeDirectory() {

    try? FileManager.default.removeItem(atPath: directory)

  }

  @Test func readsAFileOnlyItsOwnerCanReadOrWrite() throws {

    defer { removeDirectory() }

    let path: String = try file(permissions: 0o600)
    var warnings: [String] = []

    let text: String = try EnvironmentFile.read(at: path, warn: { (warning: String) -> Void in warnings.append(warning) })

    #expect(text == contents)
    #expect(warnings.isEmpty)

  }

  @Test func warnsWithoutTheContentsWhenOthersCanRead() throws {

    defer { removeDirectory() }

    let path: String = try file(permissions: 0o644)
    var warnings: [String] = []

    let text: String = try EnvironmentFile.read(at: path, warn: { (warning: String) -> Void in warnings.append(warning) })

    #expect(text == contents)
    #expect(warnings == ["insteon: warning: others can read the environment file \(path). Make it readable only by you: chmod 600 \(path)"])

  }

  @Test func refusesAFileOthersCanWrite() throws {

    defer { removeDirectory() }

    for permissions in [0o620, 0o602, 0o666] {

      let path: String = try file(named: "env-\(permissions)", permissions: permissions)

      #expect(throws: EnvironmentFileError.refused(path: path, .writableByOthers)) {

        try EnvironmentFile.read(at: path, warn: { _ in })

      }

    }

  }

  @Test(.timeLimit(.minutes(1))) func refusesADirectoryOrANamedPipeWithoutOpeningIt() throws {

    defer { removeDirectory() }

    try FileManager.default.createDirectory(atPath: directory + "/folder", withIntermediateDirectories: true)

    #expect(throws: EnvironmentFileError.refused(path: directory + "/folder", .notRegularFile)) {

      try EnvironmentFile.read(at: directory + "/folder", warn: { _ in })

    }

    // Opening a named pipe for reading would wait for a writer.
    let pipe: String = directory + "/pipe"
    try #require(mkfifo(pipe, 0o600) == 0)

    #expect(throws: EnvironmentFileError.refused(path: pipe, .notRegularFile)) {

      try EnvironmentFile.read(at: pipe, warn: { _ in })

    }

  }

  @Test func reportsAFileItCantReadAsUTF8() throws {

    defer { removeDirectory() }

    let missing: String = directory + "/missing"

    #expect(throws: EnvironmentFileError.unreadable(path: missing)) {

      try EnvironmentFile.read(at: missing, warn: { _ in })

    }

    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let binary: String = directory + "/binary"
    #expect(FileManager.default.createFile(atPath: binary, contents: Data([0xFF, 0xFE, 0x00, 0xC3])))
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: binary)

    #expect(throws: EnvironmentFileError.unreadable(path: binary)) {

      try EnvironmentFile.read(at: binary, warn: { _ in })

    }

  }

  @Test func mergesTheFileUnderTheEnvironment() throws {

    defer { removeDirectory() }

    let path: String = try file(permissions: 0o600)
    let environment: [String: String] = ["INSTEON_HUB_USER": "from-the-environment", "HOME": "/nonexistent"]

    let loaded = try EnvironmentFile.load(explicitPath: path, environment: environment, warn: { _ in })

    #expect(loaded["INSTEON_HUB_USER"] == "from-the-environment")
    #expect(loaded["INSTEON_HUB_PASSWORD"] == "not-a-real-password")
    #expect(loaded["HOME"] == "/nonexistent")

  }

  @Test func requiresOnlyAFileNamedOnTheCommandLine() throws {

    let missing: String = directory + "/missing"

    #expect(throws: EnvironmentFileError.notFound(path: missing)) {

      try EnvironmentFile.load(explicitPath: missing, environment: [:], warn: { _ in })

    }

    // The default file is optional.
    let environment: [String: String] = ["XDG_CONFIG_HOME": directory]

    #expect(try EnvironmentFile.load(explicitPath: nil, environment: environment, warn: { _ in }) == environment)

  }

  @Test func readsTheDefaultFileUnderTheConfigurationDirectory() throws {

    defer { removeDirectory() }

    try FileManager.default.createDirectory(atPath: directory + "/insteon", withIntermediateDirectories: true)
    _ = try file(named: "insteon/env", permissions: 0o600)

    let loaded = try EnvironmentFile.load(explicitPath: nil, environment: ["XDG_CONFIG_HOME": directory], warn: { _ in })

    #expect(loaded["INSTEON_HUB_USER"] == "example")

  }

}
#endif
