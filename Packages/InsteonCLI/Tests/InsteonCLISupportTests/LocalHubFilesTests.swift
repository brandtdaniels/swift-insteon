#if os(macOS) || os(Linux)
import Foundation
import Testing
import InsteonCLISupport

/// Hub files in a temporary directory, with the permissions each test gives them. The files hold
/// made-up values, never a real Hub's.
struct LocalHubFilesTests {

  let root: String = NSTemporaryDirectory() + "insteon-hub-files-" + UUID().uuidString

  var environment: [String: String] { ["XDG_CONFIG_HOME": root] }

  var hubsDirectory: String { root + "/insteon/hubs" }

  func write(_ name: String, in directory: String? = nil, containing text: String = "INSTEON_HUB_USERNAME=example-user\nINSTEON_HUB_PASSWORD=example-password\nINSTEON_HUB_HOST=192.168.1.30\n", permissions: Int) throws {

    let directory = directory ?? hubsDirectory

    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    let path = directory + "/" + name

    #expect(FileManager.default.createFile(atPath: path, contents: Data(text.utf8)))
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)

  }

  func cleanUp() {

    try? FileManager.default.removeItem(atPath: root)

  }

  @Test func readsANamedFileOnlyItsOwnerCanReadOrWrite() throws {

    defer { cleanUp() }

    try write("basement.env", permissions: 0o600)

    var warnings: [String] = []
    let loaded = try HubFiles(store: LocalHubFiles(), environment: environment).load(explicitPath: nil, hubName: "basement", warn: { warnings.append($0) })

    #expect(loaded["INSTEON_HUB_USERNAME"] == "example-user")
    #expect(loaded["INSTEON_HUB_HOST"] == "192.168.1.30")
    #expect(warnings.isEmpty)

  }

  @Test func warnsWithoutTheContentsWhenOthersCanReadANamedFile() throws {

    defer { cleanUp() }

    try write("basement.env", permissions: 0o644)

    var warnings: [String] = []

    _ = try HubFiles(store: LocalHubFiles(), environment: environment).load(explicitPath: nil, hubName: "basement", warn: { warnings.append($0) })

    #expect(warnings.count == 1)
    #expect(warnings[0].contains(hubsDirectory + "/basement.env"))
    #expect(!warnings[0].contains("example-password"))

  }

  @Test func refusesANamedFileOthersCanWrite() throws {

    defer { cleanUp() }

    try write("basement.env", permissions: 0o620)

    #expect(throws: EnvironmentFileError.refused(path: hubsDirectory + "/basement.env", .writableByOthers)) {

      try HubFiles(store: LocalHubFiles(), environment: environment).load(explicitPath: nil, hubName: "basement", warn: { _ in })

    }

  }

  @Test func refusesANamedFileThatIsADirectory() throws {

    defer { cleanUp() }

    try FileManager.default.createDirectory(atPath: hubsDirectory + "/basement.env", withIntermediateDirectories: true)

    #expect(throws: EnvironmentFileError.refused(path: hubsDirectory + "/basement.env", .notRegularFile)) {

      try HubFiles(store: LocalHubFiles(), environment: environment).load(explicitPath: nil, hubName: "basement", warn: { _ in })

    }

  }

  @Test func listsTheFilesInADirectoryAndNothingForAMissingOne() throws {

    defer { cleanUp() }

    try write("b.env", permissions: 0o600)
    try write("a.env", permissions: 0o600)

    #expect(LocalHubFiles().fileNames(inDirectory: hubsDirectory) == ["a.env", "b.env"])
    #expect(LocalHubFiles().fileNames(inDirectory: root + "/missing") == nil)
    #expect(LocalHubFiles().exists(atPath: hubsDirectory + "/a.env"))
    #expect(!LocalHubFiles().exists(atPath: hubsDirectory + "/c.env"))

  }

}
#endif
