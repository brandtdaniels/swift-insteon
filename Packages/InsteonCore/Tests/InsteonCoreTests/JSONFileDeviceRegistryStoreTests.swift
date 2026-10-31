import Foundation
import Testing
@testable import InsteonCore
import InsteonProtocol

struct JSONFileDeviceRegistryStoreTests {

  /// A directory of its own in the temporary directory, not yet made.
  static func temporaryDirectory() -> URL {

    let name: String = "JSONFileDeviceRegistryStoreTests-" + UUID().uuidString

    return FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)

  }

  /// A file in a directory that isn't made yet.
  static func file(in directory: URL) -> URL {

    directory.appending(path: "insteon", directoryHint: .isDirectory).appending(path: "identities.json", directoryHint: .notDirectory)

  }

  /// A file's POSIX permissions.
  static func permissions(of url: URL) throws -> Int {

    let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
    let permissions: NSNumber? = attributes[.posixPermissions] as? NSNumber

    return permissions?.intValue ?? -1

  }

  /// A file written as the `insteon` command's identity cache is, with no version.
  static let unversioned = Data("""
    {
      "devices" : {
        "1A.2B.3C" : { "category" : "0x02", "firmwareVersion" : "0x41", "subcategory" : "0x7A" },
        "4D.5E.6F" : { "category" : "0x01", "subcategory" : "0x7B" }
      }
    }
    """.utf8)

  /// A file as an older `insteon` command reads its identity cache: each entry on its own as
  /// a `ReportedIdentity`, and each key as an `InsteonAddress`, leaving out what doesn't read.
  struct OlderCommandsFile: Decodable {

    struct Entry: Decodable {

      var identity: ReportedIdentity?

      init(from decoder: any Decoder) throws {

        identity = try? ReportedIdentity(from: decoder)

      }

    }

    var devices: [String: Entry]

    var identities: [InsteonAddress: ReportedIdentity] {

      var identities: [InsteonAddress: ReportedIdentity] = [:]

      for (text, entry) in devices {

        guard let address = InsteonAddress(text), let identity = entry.identity else {

          continue

        }

        identities[address] = identity

      }

      return identities

    }

  }

  let snapshot = DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity, Example.lamp: Example.lampIdentity])

  // MARK: - The format

  @Test func roundTripsASnapshot() throws {

    let json: Data = try JSONFileDeviceRegistryStore.json(snapshot)
    let text = String(decoding: json, as: UTF8.self)

    #expect(try JSONFileDeviceRegistryStore.snapshot(json: json) == snapshot)
    #expect(text.contains("\"version\" : 1"))
    #expect(text.contains("\"1A.2B.3C\""))
    #expect(!text.contains("\"identity\""))

  }

  @Test func writesEachDevicesIdentityFieldsDirectlyInItsEntry() throws {

    struct FlatFile: Decodable {

      var version: Int

      var devices: [String: [String: String]]

    }

    let json: Data = try JSONFileDeviceRegistryStore.json(snapshot)
    let file: FlatFile = try JSONDecoder().decode(FlatFile.self, from: json)
    let expected: [String: [String: String]] = [
      "1A.2B.3C": ["category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41"],
      "4D.5E.6F": ["category": "0x01", "subcategory": "0x7B"]
    ]

    #expect(file.version == 1)
    #expect(file.devices == expected)

  }

  @Test func writesAFileAnOlderCommandReadsEntryByEntry() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)

    try JSONFileDeviceRegistryStore(fileURL: file).save(snapshot)

    let read: OlderCommandsFile = try JSONDecoder().decode(OlderCommandsFile.self, from: Data(contentsOf: file))

    #expect(read.devices.count == 2)
    #expect(read.devices.values.allSatisfy { (entry: OlderCommandsFile.Entry) -> Bool in entry.identity != nil })
    #expect(read.identities == snapshot.identities)

  }

  @Test func readsAFileWithNoVersionAsBareIdentities() throws {

    let read: DeviceRegistrySnapshot = try JSONFileDeviceRegistryStore.snapshot(json: Self.unversioned)

    #expect(read == snapshot)

  }

  @Test func leavesOutEntriesItCantRead() throws {

    let unversioned = Data("""
      {"devices": {
        "1A.2B.3C": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41"},
        "not an address": {"category": "0x02", "subcategory": "0x7A"},
        "4D.5E.6F": {"category": 2, "subcategory": "0x7A"},
        "7A.8B.9C": {"category": "0x02"},
        "2C.3D.4E": "0x02 0x7A",
        "5F.6A.7B": ["0x02", "0x7A"]
      }}
      """.utf8)
    let versioned = Data("""
      {"version": 1, "devices": {
        "1A.2B.3C": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41", "room": "kitchen"},
        "4D.5E.6F": {"identity": {"category": "0x02", "subcategory": "0x7A"}},
        "7A.8B.9C": "0x02 0x7A",
        "not an address": {"category": "0x02", "subcategory": "0x7A"}
      }}
      """.utf8)
    let expected = DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity])

    #expect(try JSONFileDeviceRegistryStore.snapshot(json: unversioned) == expected)
    #expect(try JSONFileDeviceRegistryStore.snapshot(json: versioned) == expected)

  }

  @Test func keepsAnEntryWhoseFirmwareVersionItCantRead() throws {

    let json = Data("""
      {"devices": {"4D.5E.6F": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "zz"}}}
      """.utf8)

    let read: DeviceRegistrySnapshot = try JSONFileDeviceRegistryStore.snapshot(json: json)

    #expect(read.identities == [Example.lamp: ReportedIdentity(category: 0x02, subcategory: 0x7A, firmwareVersion: nil)])

  }

  @Test func keepsTheSameEntryForTwoKeysThatNameOneAddress() throws {

    let plugFirst = Data("""
      {"version": 1, "devices": {
        "1A.2B.3C": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41"},
        "1a2b3c": {"category": "0x01", "subcategory": "0x7B"}
      }}
      """.utf8)
    let lampFirst = Data("""
      {"version": 1, "devices": {
        "1a2b3c": {"category": "0x01", "subcategory": "0x7B"},
        "1A.2B.3C": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41"}
      }}
      """.utf8)
    // "1a2b3c" sorts after "1A.2B.3C", so its entry is kept.
    let expected = DeviceRegistrySnapshot(identities: [Example.plug: Example.lampIdentity])

    for _ in 0..<20 {

      #expect(try JSONFileDeviceRegistryStore.snapshot(json: plugFirst) == expected)
      #expect(try JSONFileDeviceRegistryStore.snapshot(json: lampFirst) == expected)

    }

  }

  @Test(arguments: ["not json", "[]", "{}", "{\"devices\": []}", "{\"version\": \"1\", \"devices\": {}}", "{\"version\": 0, \"devices\": {}}", "{\"version\": 1}"])
  func rejectsContentsThatArentARegistryFile(_ text: String) {

    #expect(throws: DeviceRegistryStoreError.malformedContents) {

      try JSONFileDeviceRegistryStore.snapshot(json: Data(text.utf8))

    }

  }

  @Test func rejectsANewerFormat() {

    #expect(throws: DeviceRegistryStoreError.unsupportedVersion(2)) {

      try JSONFileDeviceRegistryStore.snapshot(json: Data("{\"version\": 2, \"devices\": {}}".utf8))

    }

  }

  // MARK: - The file

  @Test func readsNoDevicesWhenTheresNoFile() throws {

    let directory: URL = Self.temporaryDirectory()
    let store = JSONFileDeviceRegistryStore(fileURL: Self.file(in: directory))

    #expect(try store.load().isEmpty)

  }

  @Test func savesAndLoadsAFileOnlyTheUserCanRead() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)

    try store.save(snapshot)

    #expect(try store.load() == snapshot)
    #expect(try Self.permissions(of: file) == 0o600)
    #expect(try Self.permissions(of: file.deletingLastPathComponent()) == 0o700)

  }

  @Test func leavesTheFilesDirectoryWithItsPermissionsWhenItsThere() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let folder: String = file.deletingLastPathComponent().path(percentEncoded: false)

    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o751)], ofItemAtPath: folder)

    try JSONFileDeviceRegistryStore(fileURL: file).save(snapshot)

    #expect(try Self.permissions(of: file.deletingLastPathComponent()) == 0o751)
    #expect(try Self.permissions(of: file) == 0o600)

  }

  @Test(.timeLimit(.minutes(1))) func savesThroughTheProtocol() async throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: any DeviceRegistryStore = JSONFileDeviceRegistryStore(fileURL: Self.file(in: directory))
    let registry = DeviceRegistry(catalog: Example.catalog, snapshot: try await store.load())

    await registry.record(Example.plugIdentity, for: Example.plug)
    try await store.save(await registry.snapshot)

    let restored = DeviceRegistry(catalog: Example.catalog, snapshot: try await store.load())

    #expect(await restored.device(Example.plug)?.deviceDescription.profile == Example.plugProfile)

  }

  @Test func readsTheCommandsIdentityCacheAndSavesItWithAVersion() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)

    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.unversioned.write(to: file)

    var read: DeviceRegistrySnapshot = try store.load()

    #expect(read == snapshot)

    read.identities[Example.sensor] = Example.plugIdentity
    try store.save(read)

    #expect(try store.load() == read)
    #expect(try Data(contentsOf: file) == JSONFileDeviceRegistryStore.json(read))

  }

  @Test func replacesTheFileWholeAndLeavesNothingElseBehind() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)
    let smaller = DeviceRegistrySnapshot(identities: [Example.lamp: Example.lampIdentity])

    try store.save(snapshot)
    try store.save(smaller)

    let names: [String] = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path(percentEncoded: false))

    #expect(try Data(contentsOf: file) == JSONFileDeviceRegistryStore.json(smaller))
    #expect(names == ["identities.json"])
    #expect(try Self.permissions(of: file) == 0o600)

  }

  @Test func failsOnACorruptFileAndLeavesItAsItIs() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)
    let corrupt = Data("{\"devices\": {\"1A.2B.3C\": ".utf8)

    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try corrupt.write(to: file)

    #expect(throws: DeviceRegistryStoreError.malformedContents) {

      try store.load()

    }

    #expect(throws: DeviceRegistryStoreError.malformedContents) {

      try store.save(snapshot)

    }

    #expect(try Data(contentsOf: file) == corrupt)

  }

  @Test func leavesAFileInANewerFormatAsItIs() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)
    let newer = Data("{\"version\": 2, \"devices\": {}, \"modem\": {}}".utf8)

    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try newer.write(to: file)

    #expect(throws: DeviceRegistryStoreError.unsupportedVersion(2)) {

      try store.save(snapshot)

    }

    #expect(try Data(contentsOf: file) == newer)

  }

  @Test func readsOnlyARegularFile() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)

    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

    #expect(throws: DeviceRegistryStoreError.unreadableFile) {

      try store.load()

    }

  }

  @Test func leavesADirectoryAtThePathAsItIs() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)

    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

    #expect(throws: DeviceRegistryStoreError.unreadableFile) {

      try store.save(snapshot)

    }

    var isDirectory: ObjCBool = false
    let exists: Bool = FileManager.default.fileExists(atPath: file.path(percentEncoded: false), isDirectory: &isDirectory)

    #expect(exists)
    #expect(isDirectory.boolValue)

  }

  @Test func leavesASymbolicLinkAtThePathAsItIs() throws {

    let directory: URL = Self.temporaryDirectory()

    defer { try? FileManager.default.removeItem(at: directory) }

    let file: URL = Self.file(in: directory)
    let target: URL = directory.appending(path: "elsewhere.json", directoryHint: .notDirectory)
    let store = JSONFileDeviceRegistryStore(fileURL: file)
    let contents: Data = try JSONFileDeviceRegistryStore.json(snapshot)

    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: target)
    try FileManager.default.createSymbolicLink(atPath: file.path(percentEncoded: false), withDestinationPath: target.path(percentEncoded: false))

    #expect(throws: DeviceRegistryStoreError.unreadableFile) {

      try store.load()

    }

    #expect(throws: DeviceRegistryStoreError.unreadableFile) {

      try store.save(DeviceRegistrySnapshot())

    }

    let destination: String = try FileManager.default.destinationOfSymbolicLink(atPath: file.path(percentEncoded: false))

    #expect(destination == target.path(percentEncoded: false))
    #expect(try Data(contentsOf: target) == contents)

  }

}
