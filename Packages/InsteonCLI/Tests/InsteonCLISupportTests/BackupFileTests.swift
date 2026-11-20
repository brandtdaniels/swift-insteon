import Foundation
import Testing
import InsteonCLISupport

/// Where a backup is written and read: private to the user, and never over a file nobody agreed
/// to replace.
struct BackupFileTests {

  /// A directory of its own, removed when the test ends.
  final class Directory {

    let path: String

    init() throws {

      path = NSTemporaryDirectory() + "backup-tests-" + UUID().uuidString

      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

    }

    deinit { try? FileManager.default.removeItem(atPath: path) }

    func file(_ name: String) -> String { path + "/" + name }

    func mode(_ name: String) throws -> Int {

      let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: file(name))

      return (attributes[.posixPermissions] as? Int) ?? -1

    }

  }

  let contents: Data = Data("{\"format\": 1}\n".utf8)

  @Test func writesAFileReadableOnlyByItsOwner() throws {

    let directory = try Directory()

    try BackupFile.write(contents, to: directory.file("home.json"), overwrites: false)

    #expect(try directory.mode("home.json") == 0o600)
    #expect(try BackupFile.read(directory.file("home.json")) == contents)

  }

  @Test func writesModeSixHundredWhateverTheProcessMask() throws {

    let directory = try Directory()
    let previous: mode_t = umask(0)

    defer { umask(previous) }

    try BackupFile.write(contents, to: directory.file("home.json"), overwrites: false)

    #expect(try directory.mode("home.json") == 0o600)

  }

  @Test func refusesToReplaceAFileWithoutForceAndLeavesItAsItWas() throws {

    let directory = try Directory()
    let path: String = directory.file("home.json")

    try Data("old".utf8).write(to: URL(fileURLWithPath: path))

    #expect(throws: CommandFailure.self) { try BackupFile.checkWritable(path, overwrites: false) }
    #expect(throws: CommandFailure.self) { try BackupFile.write(contents, to: path, overwrites: false) }
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("old".utf8))

  }

  @Test func saysHowToReplaceAFile() throws {

    let directory = try Directory()
    let path: String = directory.file("home.json")

    try Data("old".utf8).write(to: URL(fileURLWithPath: path))

    do {

      try BackupFile.checkWritable(path, overwrites: false)

      Issue.record("A file that exists was accepted.")

    } catch {

      #expect(error.description.contains("--force"))
      #expect(error.description.contains("nothing was read"))

    }

  }

  @Test func replacesAFileWithForceAndKeepsItPrivate() throws {

    let directory = try Directory()
    let path: String = directory.file("home.json")

    try Data("old".utf8).write(to: URL(fileURLWithPath: path))
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
    try BackupFile.checkWritable(path, overwrites: true)
    try BackupFile.write(contents, to: path, overwrites: true)

    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == contents)
    #expect(try directory.mode("home.json") == 0o600)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["home.json"])

  }

  @Test func acceptsAPathWithNothingThere() throws {

    let directory = try Directory()

    try BackupFile.checkWritable(directory.file("home.json"), overwrites: false)

  }

  @Test func refusesToWriteWhereADirectoryIs() throws {

    let directory = try Directory()

    #expect(throws: CommandFailure.self) { try BackupFile.checkWritable(directory.path, overwrites: true) }

  }

  @Test func neverFollowsASymbolicLinkWhenCreating() throws {

    let directory = try Directory()
    let target: String = directory.file("target.json")

    try FileManager.default.createSymbolicLink(atPath: directory.file("link.json"), withDestinationPath: target)

    #expect(throws: CommandFailure.self) { try BackupFile.write(contents, to: directory.file("link.json"), overwrites: false) }
    #expect(!FileManager.default.fileExists(atPath: target))

  }

  @Test func saysWhyAFileCantBeRead() throws {

    let directory = try Directory()

    #expect(throws: CommandFailure.self) { _ = try BackupFile.read(directory.file("missing.json")) }
    #expect(throws: CommandFailure.self) { _ = try BackupFile.read(directory.path) }

  }

}
