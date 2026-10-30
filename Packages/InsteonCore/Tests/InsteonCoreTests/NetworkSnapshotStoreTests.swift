import Foundation
import Testing
import InsteonCore
import InsteonLinking
import InsteonProtocol

/// Keeping a whole network's snapshot in the registry's JSON file.
struct NetworkSnapshotStoreTests {

  static let controls = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: Example.plug, data1: 0x02, data2: 0x7A, data3: 0x41)

  static let responds = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: InsteonAddress(0x11, 0x22, 0x33), data1: 0xFF, data2: 0x1C, data3: 0x01)

  static let end = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  static let plugDatabase = AllLinkDatabaseCopy(
    delta: 0x05,
    records: [
      AllLinkRecordResponse(sender: Example.plug, address: 0x0FFF, record: responds),
      AllLinkRecordResponse(sender: Example.plug, address: 0x0FF7, record: end, hasIntactChecksum: false)
    ]
  )

  static let hub = HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x11, 0x22, 0x33))

  /// A snapshot with every field: the plug with an identity and everything the network
  /// learned, the lamp with only an identity, and the sensor with no identity.
  static let snapshot = NetworkSnapshot(
    registry: DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity, Example.lamp: Example.lampIdentity]),
    devices: [
      Example.plug: NetworkDeviceState(engine: .i2cs, allLinkDatabase: plugDatabase, level: 0xFF, lastSeen: Date(timeIntervalSince1970: 1_800_000_000)),
      Example.sensor: NetworkDeviceState(engine: .i2cs, lastSeen: Date(timeIntervalSince1970: 1_800_000_060))
    ],
    modemDatabase: [controls],
    hub: hub
  )

  static func temporaryFile() -> (directory: URL, file: URL) {

    let directory: URL = JSONFileDeviceRegistryStoreTests.temporaryDirectory()

    return (directory, JSONFileDeviceRegistryStoreTests.file(in: directory))

  }

  // MARK: - The format

  @Test func roundTripsANetworkSnapshot() throws {

    let json: Data = try JSONFileDeviceRegistryStore.json(Self.snapshot)

    #expect(try JSONFileDeviceRegistryStore.networkSnapshot(json: json) == Self.snapshot)
    #expect(try JSONFileDeviceRegistryStore.snapshot(json: json) == Self.snapshot.registry)

  }

  @Test func writesTheFormatItDocuments() throws {

    let json: Data = try JSONFileDeviceRegistryStore.json(Self.snapshot)
    let text = String(decoding: json, as: UTF8.self)

    #expect(text.contains("\"version\" : 1"))
    #expect(text.contains("\"engine\" : \"i2cs\""))
    #expect(text.contains("\"level\" : \"0xFF\""))
    #expect(text.contains("\"lastSeen\" : \"2027-01-15T08:00:00Z\""))
    #expect(text.contains("\"delta\" : \"0x05\""))
    #expect(text.contains("\"address\" : \"0x0FFF\""))
    #expect(text.contains("\"bytes\" : \"A2 01 11 22 33 FF 1C 01\""))
    #expect(text.contains("\"checksumFailed\" : true"))
    #expect(text.contains("\"E2 00 1A 2B 3C 02 7A 41\""))
    #expect(text.contains("\"host\" : \"192.0.2.10\""))
    #expect(text.contains("\"port\" : 25105"))
    #expect(text.contains("\"insteonID\" : \"11.22.33\""))

  }

  @Test func keepsEachDevicesIdentityFieldsDirectlyInItsEntry() throws {

    struct Entry: Decodable {

      var category: String?

      var subcategory: String?

      var firmwareVersion: String?

      var engine: String?

    }

    struct File: Decodable {

      var version: Int

      var devices: [String: Entry]

    }

    let file: File = try JSONDecoder().decode(File.self, from: JSONFileDeviceRegistryStore.json(Self.snapshot))

    #expect(file.version == 1)
    #expect(file.devices["1A.2B.3C"]?.category == "0x02")
    #expect(file.devices["1A.2B.3C"]?.subcategory == "0x7A")
    #expect(file.devices["1A.2B.3C"]?.firmwareVersion == "0x41")
    #expect(file.devices["1A.2B.3C"]?.engine == "i2cs")
    #expect(file.devices["0A.0B.0C"]?.category == nil)
    #expect(file.devices["0A.0B.0C"]?.engine == "i2cs")

  }

  @Test func writesAFileAnOlderCommandReadsEntryByEntry() throws {

    let json: Data = try JSONFileDeviceRegistryStore.json(Self.snapshot)
    let read: JSONFileDeviceRegistryStoreTests.OlderCommandsFile = try JSONDecoder().decode(JSONFileDeviceRegistryStoreTests.OlderCommandsFile.self, from: json)

    #expect(read.identities == Self.snapshot.registry.identities)

  }

  /// A file as a store that reads only identities reads it: a version that must be 1, and
  /// each entry on its own as a `ReportedIdentity`, leaving out what doesn't read.
  @Test func writesAFileAnOlderStoreReads() throws {

    struct Lenient: Decodable {

      var identity: ReportedIdentity?

      init(from decoder: any Decoder) throws {

        identity = try? ReportedIdentity(from: decoder)

      }

    }

    struct OlderStoresFile: Decodable {

      var version: Int?

      var devices: [String: Lenient]

    }

    let file: OlderStoresFile = try JSONDecoder().decode(OlderStoresFile.self, from: JSONFileDeviceRegistryStore.json(Self.snapshot))
    let identities: [String: ReportedIdentity] = file.devices.compactMapValues { (entry: Lenient) -> ReportedIdentity? in entry.identity }

    #expect(file.version == 1)
    #expect(identities == ["1A.2B.3C": Example.plugIdentity, "4D.5E.6F": Example.lampIdentity])

  }

  @Test func readsAVersion1FileWithOnlyIdentities() throws {

    let json = Data("""
      {"version": 1, "devices": {"1A.2B.3C": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41"}}}
      """.utf8)

    let read: NetworkSnapshot = try JSONFileDeviceRegistryStore.networkSnapshot(json: json)

    #expect(read == NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity])))

  }

  @Test func readsAFileWithNoVersion() throws {

    let read: NetworkSnapshot = try JSONFileDeviceRegistryStore.networkSnapshot(json: JSONFileDeviceRegistryStoreTests.unversioned)

    #expect(read.registry == DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity, Example.lamp: Example.lampIdentity]))
    #expect(read.devices.isEmpty)
    #expect(read.modemDatabase == nil)
    #expect(read.hub == nil)

  }

  @Test func leavesOutEachFieldItCantReadOnItsOwn() throws {

    let json = Data("""
      {"version": 1,
       "devices": {
         "1A.2B.3C": {"category": "0x02", "subcategory": "0x7A", "firmwareVersion": "0x41",
                      "engine": "i9", "level": "full", "lastSeen": "yesterday",
                      "allLinkDatabase": {"delta": "0x05", "records": [{"address": "0x0FFF", "bytes": "A2 01 11 22"}]}},
         "4D.5E.6F": {"category": "0x01", "subcategory": "0x7B", "level": "0x80",
                      "allLinkDatabase": {"delta": "5", "records": []}}
       },
       "modem": {"allLinkDatabase": ["E2 00 1A 2B 3C 02 7A 41", "not a record"]},
       "hub": {"host": "192.0.2.10", "port": 0}
      }
      """.utf8)

    let read: NetworkSnapshot = try JSONFileDeviceRegistryStore.networkSnapshot(json: json)

    #expect(read.registry.identities == [Example.plug: Example.plugIdentity, Example.lamp: Example.lampIdentity])
    #expect(read.devices == [Example.lamp: NetworkDeviceState(level: 0x80)])
    #expect(read.modemDatabase == nil)
    #expect(read.hub == nil)

  }

  @Test func readsAHubWithoutAnInsteonID() throws {

    let json = Data("""
      {"version": 1, "devices": {}, "hub": {"host": "192.0.2.10", "port": 25105, "insteonID": "not an address"}}
      """.utf8)

    #expect(try JSONFileDeviceRegistryStore.networkSnapshot(json: json).hub == HubLocation(host: "192.0.2.10", port: 25105))

  }

  @Test func neverWritesCredentials() throws {

    let json: Data = try JSONFileDeviceRegistryStore.json(Self.snapshot)
    let text: String = String(decoding: json, as: UTF8.self).lowercased()

    for word in ["password", "user", "credential", "secret", "token", "mac"] {

      #expect(!text.contains(word), "The file has \(word).")

    }

  }

  @Test func rejectsANewerFormat() {

    #expect(throws: DeviceRegistryStoreError.unsupportedVersion(2)) {

      try JSONFileDeviceRegistryStore.networkSnapshot(json: Data("{\"version\": 2, \"devices\": {}}".utf8))

    }

  }

  // MARK: - The file

  @Test func savesAndLoadsANetworkSnapshotOnlyTheUserCanRead() throws {

    let (directory, file) = Self.temporaryFile()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store = JSONFileDeviceRegistryStore(fileURL: file)

    try store.saveNetwork(Self.snapshot)

    #expect(try store.loadNetwork() == Self.snapshot)
    #expect(try store.load() == Self.snapshot.registry)
    #expect(try JSONFileDeviceRegistryStoreTests.permissions(of: file) == 0o600)

  }

  @Test func savingARegistryKeepsWhatTheNetworkLearned() throws {

    let (directory, file) = Self.temporaryFile()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store = JSONFileDeviceRegistryStore(fileURL: file)
    var registry: DeviceRegistrySnapshot = Self.snapshot.registry

    try store.saveNetwork(Self.snapshot)

    registry.identities[Example.lamp] = nil
    try store.save(registry)

    var expected: NetworkSnapshot = Self.snapshot
    expected.registry = registry

    #expect(try store.loadNetwork() == expected)

  }

  @Test func leavesAFileItCantReadAsItIs() throws {

    let (directory, file) = Self.temporaryFile()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store = JSONFileDeviceRegistryStore(fileURL: file)
    let newer = Data("{\"version\": 2, \"devices\": {}}".utf8)

    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try newer.write(to: file)

    #expect(throws: DeviceRegistryStoreError.unsupportedVersion(2)) {

      try store.saveNetwork(Self.snapshot)

    }

    #expect(try Data(contentsOf: file) == newer)

  }

  @Test func savesThroughTheProtocol() async throws {

    let (directory, file) = Self.temporaryFile()

    defer { try? FileManager.default.removeItem(at: directory) }

    let store: any NetworkSnapshotStore = JSONFileDeviceRegistryStore(fileURL: file)

    #expect(try await store.loadNetwork().isEmpty)

    try await store.saveNetwork(Self.snapshot)

    #expect(try await store.loadNetwork() == Self.snapshot)

  }

}
