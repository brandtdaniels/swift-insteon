import Foundation
import InsteonLinking
import InsteonProtocol

/// Keeps a ``DeviceRegistry``'s devices, or a whole ``NetworkSnapshot``, in a JSON file,
/// readable only by the current user.
///
/// The file names its format's version, and holds each device by its address, with the
/// identity's fields directly in the device's entry. What a ``DeviceNetwork`` learned about a
/// device goes beside them: its engine, a copy of its ALL-Link database with the delta it was
/// read at, its last known level and when it last answered. The modem's ALL-Link database and
/// the Hub's location go beside the devices:
///
/// ```json
/// {
///   "devices" : {
///     "1A.2B.3C" : {
///       "allLinkDatabase" : {
///         "delta" : "0x05",
///         "records" : [
///           { "address" : "0x0FFF", "bytes" : "E2 01 11 22 33 FF 1C 01" },
///           { "address" : "0x0FF7", "bytes" : "00 00 00 00 00 00 00 00" }
///         ]
///       },
///       "category" : "0x02",
///       "engine" : "i2cs",
///       "firmwareVersion" : "0x41",
///       "lastSeen" : "2026-01-02T03:04:05Z",
///       "level" : "0xFF",
///       "subcategory" : "0x2A"
///     }
///   },
///   "hub" : { "host" : "192.0.2.10", "insteonID" : "11.22.33", "port" : 25105 },
///   "modem" : { "allLinkDatabase" : [ "E2 01 1A 2B 3C 02 2A 41" ] },
///   "version" : 1
/// }
/// ```
///
/// Each entry has the same keys as an entry in the `insteon` command's identity cache, which
/// has no version, so a reader of that cache that ignores keys it doesn't know reads the
/// devices in this file too. Every other field is one such a reader ignores, so the format
/// stays at version 1. A record's bytes are its flags, group, address and three data bytes;
/// a record whose checksum didn't check out when it was read also has `"checksumFailed" :
/// true`. A device the network knows nothing about but its identity has only the identity's
/// fields, and a device whose identity isn't known has only the other fields.
///
/// The file never holds credentials, the Hub's MAC address, names or rooms.
///
/// The store also reads a file with no version, as the `insteon` command's identity cache is
/// written, and writes it back with a version the next time it saves. A device entry that
/// doesn't read as an address and an identity is left out of the registry, so one bad entry
/// doesn't lose the others, and a field that doesn't read is left out on its own: a device
/// keeps its identity when its ALL-Link database doesn't read. When two keys name one address,
/// such as `"1A.2B.3C"` and `"1a2b3c"`, the entry whose key sorts last is kept.
///
/// Saving writes a temporary file of its own, readable only by the current user, then moves it
/// into place, so a reader never sees half a file. If the file's directory isn't there, the
/// store creates it readable only by the current user; a directory that's already there keeps
/// its permissions, and any directory above it that the store creates has the system's default
/// permissions. The store never replaces a file it can't read, such as one written in a newer
/// format or a symbolic link, so nothing in it is lost. Saving only a registry's devices with
/// ``save(_:)`` keeps everything else the file holds. Two processes that save at the same
/// time each write what they hold, so the last one to save wins.
///
/// ```swift
/// let store = JSONFileDeviceRegistryStore(fileURL: url)
/// let registry = DeviceRegistry(catalog: catalog, snapshot: try store.load())
/// ```
public struct JSONFileDeviceRegistryStore: DeviceRegistryStore, NetworkSnapshotStore {

  /// The version of the format the store writes, and the newest it reads.
  public static let formatVersion: Int = 1

  /// The file's location.
  public let fileURL: URL

  /// Creates a store that keeps devices in a file.
  ///
  /// - Parameter fileURL: The file's location. The file and its directory needn't exist yet.
  public init(fileURL: URL) {

    self.fileURL = fileURL

  }

  /// Reads the devices in the file.
  ///
  /// - Returns: The devices, or an empty snapshot if there's no file.
  /// - Throws: ``DeviceRegistryStoreError/unreadableFile`` if something other than a regular
  ///   file is there or it can't be read, ``DeviceRegistryStoreError/malformedContents`` if it
  ///   isn't a registry file, and ``DeviceRegistryStoreError/unsupportedVersion(_:)`` if it's
  ///   in a newer format.
  public func load() throws -> DeviceRegistrySnapshot {

    try loadNetwork().registry

  }

  /// Replaces the devices' identities in the file with the ones in a snapshot, keeping
  /// everything else the file holds, such as copies of ALL-Link databases.
  ///
  /// A file that's already there is replaced only if it reads as a registry file, so a file
  /// that ``load()`` can't read is never lost.
  ///
  /// - Parameter snapshot: The devices to keep.
  /// - Throws: The error ``load()`` throws for a file already there that it can't read, or
  ///   ``DeviceRegistryStoreError/writeFailed(code:)`` if the file couldn't be written, which
  ///   leaves the file that was there as it was.
  public func save(_ snapshot: DeviceRegistrySnapshot) throws {

    var network: NetworkSnapshot = try loadNetwork()
    network.registry = snapshot

    try PrivateFile.replace(path, with: Self.json(network))

  }

  /// Reads everything in the file.
  ///
  /// - Returns: The snapshot, or an empty one if there's no file.
  /// - Throws: The errors ``load()`` throws.
  public func loadNetwork() throws -> NetworkSnapshot {

    guard let data = try contents() else {

      return NetworkSnapshot()

    }

    return try Self.networkSnapshot(json: data)

  }

  /// Replaces the file with a snapshot.
  ///
  /// A file that's already there is replaced only if it reads as a registry file, so a file
  /// that ``loadNetwork()`` can't read is never lost.
  ///
  /// - Parameter snapshot: The snapshot to keep.
  /// - Throws: The errors ``save(_:)`` throws.
  public func saveNetwork(_ snapshot: NetworkSnapshot) throws {

    _ = try loadNetwork()

    try PrivateFile.replace(path, with: Self.json(snapshot))

  }

  /// Reads devices from a registry file's contents, with or without a version.
  ///
  /// - Parameter json: The file's contents.
  /// - Returns: The devices. An entry that doesn't read as an address and an identity is left
  ///   out.
  /// - Throws: ``DeviceRegistryStoreError/malformedContents`` if the contents aren't a registry
  ///   file, and ``DeviceRegistryStoreError/unsupportedVersion(_:)`` if they're in a newer
  ///   format.
  public static func snapshot(json: Data) throws -> DeviceRegistrySnapshot {

    try networkSnapshot(json: json).registry

  }

  /// Reads a snapshot from a registry file's contents, with or without a version.
  ///
  /// - Parameter json: The file's contents.
  /// - Returns: The snapshot. A field that doesn't read is left out, and so is a device entry
  ///   in which nothing reads.
  /// - Throws: The errors ``snapshot(json:)`` throws.
  public static func networkSnapshot(json: Data) throws -> NetworkSnapshot {

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let header: Header

    do {

      header = try decoder.decode(Header.self, from: json)

    } catch {

      throw DeviceRegistryStoreError.malformedContents

    }

    if let version = header.version {

      guard version <= formatVersion else {

        throw DeviceRegistryStoreError.unsupportedVersion(version)

      }

      guard version == formatVersion else {

        throw DeviceRegistryStoreError.malformedContents

      }

    }

    // A device's entry is read the same way with or without a version: the identity's fields
    // are in the entry itself.
    let file: StoredFile = try decode(StoredFile.self, from: json, with: decoder)
    let entries: [String: StoredDevice] = file.devices.compactMapValues { (entry: Lenient<StoredDevice>) -> StoredDevice? in entry.value }

    var identities: [InsteonAddress: ReportedIdentity] = [:]
    var devices: [InsteonAddress: NetworkDeviceState] = [:]

    // In key order, so of two keys for one address, such as "1A.2B.3C" and "1a2b3c", the one
    // that sorts last is always kept.
    for key in entries.keys.sorted() {

      guard let address = InsteonAddress(key), let entry = entries[key] else {

        continue

      }

      if let identity = entry.identity {

        identities[address] = identity

      }

      let state: NetworkDeviceState = entry.state(of: address)

      if !state.isEmpty {

        devices[address] = state

      }

    }

    return NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: identities),
      devices: devices,
      modemDatabase: file.modem?.value?.allLinkDatabase,
      hub: file.hub?.value?.location
    )

  }

  /// A snapshot as a registry file's contents, with a version, and with the devices in address
  /// order.
  ///
  /// - Parameter snapshot: The devices.
  /// - Returns: The file's contents.
  /// - Throws: `EncodingError` if the snapshot can't be encoded.
  public static func json(_ snapshot: DeviceRegistrySnapshot) throws -> Data {

    try json(NetworkSnapshot(registry: snapshot))

  }

  /// A network snapshot as a registry file's contents, with a version, and with the devices in
  /// address order.
  ///
  /// - Parameter snapshot: The snapshot.
  /// - Returns: The file's contents.
  /// - Throws: `EncodingError` if the snapshot can't be encoded.
  public static func json(_ snapshot: NetworkSnapshot) throws -> Data {

    var devices: [String: StoredDevice] = [:]
    let addresses: Set<InsteonAddress> = Set(snapshot.registry.identities.keys).union(snapshot.devices.keys)

    for address in addresses {

      let identity: ReportedIdentity? = snapshot.registry.identities[address]
      let state: NetworkDeviceState = snapshot.devices[address] ?? NetworkDeviceState()

      guard identity != nil || !state.isEmpty else {

        continue

      }

      devices["\(address)"] = StoredDevice(identity: identity, state: state)

    }

    let file = StoredFile(
      version: formatVersion,
      devices: devices,
      modem: snapshot.modemDatabase.map { (records: [AllLinkRecord]) -> StoredModem in StoredModem(allLinkDatabase: records) },
      hub: snapshot.hub.map { (hub: HubLocation) -> StoredHub in StoredHub(hub) }
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    return try encoder.encode(file)

  }

  // MARK: - The file

  private var path: String {

    fileURL.path(percentEncoded: false)

  }

  /// The file's contents, or `nil` if there's no file.
  private func contents() throws -> Data? {

    let attributes: [FileAttributeKey: Any]

    do {

      attributes = try FileManager.default.attributesOfItem(atPath: path)

    } catch {

      guard FileManager.default.fileExists(atPath: path) else {

        return nil

      }

      throw DeviceRegistryStoreError.unreadableFile

    }

    // Only a regular file is read, so a named pipe can't block the caller.
    guard (attributes[.type] as? FileAttributeType) == .typeRegular, let data = FileManager.default.contents(atPath: path) else {

      throw DeviceRegistryStoreError.unreadableFile

    }

    return data

  }

  private static func decode<File: Decodable>(_ type: File.Type, from json: Data, with decoder: JSONDecoder) throws -> File {

    do {

      return try decoder.decode(type, from: json)

    } catch {

      throw DeviceRegistryStoreError.malformedContents

    }

  }

  // MARK: - The format

  /// The part of every format that says which format it is.
  private struct Header: Decodable {

    var version: Int?

  }

  /// The file, with a version or, as the `insteon` command's identity cache is written,
  /// without one.
  private struct StoredFile: Codable {

    var version: Int?

    var devices: [String: Lenient<StoredDevice>]

    var modem: Lenient<StoredModem>?

    var hub: Lenient<StoredHub>?

    init(version: Int, devices: [String: StoredDevice], modem: StoredModem?, hub: StoredHub?) {

      self.version = version
      self.devices = devices.mapValues { (device: StoredDevice) -> Lenient<StoredDevice> in Lenient(device) }
      self.modem = modem.map { (modem: StoredModem) -> Lenient<StoredModem> in Lenient(modem) }
      self.hub = hub.map { (hub: StoredHub) -> Lenient<StoredHub> in Lenient(hub) }

    }

  }

  /// A device's entry: the identity's fields, directly in the entry, so a reader that decodes
  /// each entry as a `ReportedIdentity` reads it, and what the network learned about the
  /// device beside them. Each field that doesn't read is left out on its own.
  private struct StoredDevice: Codable {

    private enum CodingKeys: String, CodingKey {

      case engine
      case allLinkDatabase
      case level
      case lastSeen

    }

    var identity: ReportedIdentity?

    var engine: InsteonEngine?

    var allLinkDatabase: StoredDatabase?

    var level: UInt8?

    var lastSeen: Date?

    init(identity: ReportedIdentity?, state: NetworkDeviceState) {

      self.identity = identity
      self.engine = state.engine
      self.allLinkDatabase = state.allLinkDatabase.map { (copy: AllLinkDatabaseCopy) -> StoredDatabase in StoredDatabase(copy) }
      self.level = state.level
      self.lastSeen = state.lastSeen

    }

    init(from decoder: any Decoder) throws {

      // An entry that isn't an object isn't a device.
      let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

      identity = try? ReportedIdentity(from: decoder)

      let engineName: String? = try? container.decodeIfPresent(String.self, forKey: .engine)
      let levelText: String? = try? container.decodeIfPresent(String.self, forKey: .level)

      engine = engineName.flatMap(StoredEngine.engine(named:))
      allLinkDatabase = try? container.decodeIfPresent(StoredDatabase.self, forKey: .allLinkDatabase)
      level = levelText.flatMap(StoredBytes.byte(_:))
      lastSeen = try? container.decodeIfPresent(Date.self, forKey: .lastSeen)

    }

    func encode(to encoder: any Encoder) throws {

      if let identity {

        try identity.encode(to: encoder)

      }

      var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

      try container.encodeIfPresent(engine.map(StoredEngine.name(of:)), forKey: .engine)
      try container.encodeIfPresent(allLinkDatabase, forKey: .allLinkDatabase)
      try container.encodeIfPresent(level.map(StoredBytes.text(_:)), forKey: .level)
      try container.encodeIfPresent(lastSeen, forKey: .lastSeen)

    }

    /// What the entry says about the device besides its identity.
    func state(of device: InsteonAddress) -> NetworkDeviceState {

      NetworkDeviceState(
        engine: engine,
        allLinkDatabase: allLinkDatabase?.copy(of: device),
        level: level,
        lastSeen: lastSeen
      )

    }

  }

  /// A copy of a device's ALL-Link database. It reads only whole: a copy with a record that
  /// doesn't read is left out, so a database is never handed back with records missing.
  private struct StoredDatabase: Codable {

    private enum CodingKeys: String, CodingKey {

      case delta
      case records

    }

    var delta: UInt8

    var records: [StoredRecord]

    init(_ copy: AllLinkDatabaseCopy) {

      delta = copy.delta
      records = copy.records.map { (response: AllLinkRecordResponse) -> StoredRecord in StoredRecord(response) }

    }

    init(from decoder: any Decoder) throws {

      let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
      let deltaText: String = try container.decode(String.self, forKey: .delta)

      guard let delta = StoredBytes.byte(deltaText) else {

        throw DecodingError.dataCorruptedError(forKey: .delta, in: container, debugDescription: "Expected 0x and two hexadecimal digits.")

      }

      self.delta = delta
      self.records = try container.decode([StoredRecord].self, forKey: .records)

    }

    func encode(to encoder: any Encoder) throws {

      var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

      try container.encode(StoredBytes.text(delta), forKey: .delta)
      try container.encode(records, forKey: .records)

    }

    /// The copy, with each record from the device.
    func copy(of device: InsteonAddress) -> AllLinkDatabaseCopy {

      AllLinkDatabaseCopy(
        delta: delta,
        records: records.map { (record: StoredRecord) -> AllLinkRecordResponse in record.response(from: device) }
      )

    }

  }

  /// A record of a device's ALL-Link database, at its address in the database.
  private struct StoredRecord: Codable {

    private enum CodingKeys: String, CodingKey {

      case address
      case bytes
      case checksumFailed

    }

    var address: UInt16

    var record: AllLinkRecord

    var hasIntactChecksum: Bool

    init(_ response: AllLinkRecordResponse) {

      address = response.address
      record = response.record
      hasIntactChecksum = response.hasIntactChecksum

    }

    init(from decoder: any Decoder) throws {

      let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
      let addressText: String = try container.decode(String.self, forKey: .address)
      let bytesText: String = try container.decode(String.self, forKey: .bytes)
      let checksumFailed: Bool = try container.decodeIfPresent(Bool.self, forKey: .checksumFailed) ?? false

      guard let address = StoredBytes.memoryAddress(addressText), let record = StoredBytes.record(bytesText) else {

        throw DecodingError.dataCorruptedError(forKey: .bytes, in: container, debugDescription: "Expected a record's address and eight bytes.")

      }

      self.address = address
      self.record = record
      self.hasIntactChecksum = !checksumFailed

    }

    func encode(to encoder: any Encoder) throws {

      var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

      try container.encode(StoredBytes.text(memoryAddress: address), forKey: .address)
      try container.encode(StoredBytes.text(record: record), forKey: .bytes)

      if !hasIntactChecksum {

        try container.encode(true, forKey: .checksumFailed)

      }

    }

    func response(from device: InsteonAddress) -> AllLinkRecordResponse {

      AllLinkRecordResponse(sender: device, address: address, record: record, hasIntactChecksum: hasIntactChecksum)

    }

  }

  /// The modem's own ALL-Link database, as last read. It reads only whole.
  private struct StoredModem: Codable {

    private enum CodingKeys: String, CodingKey {

      case allLinkDatabase

    }

    var allLinkDatabase: [AllLinkRecord]

    init(allLinkDatabase: [AllLinkRecord]) {

      self.allLinkDatabase = allLinkDatabase

    }

    init(from decoder: any Decoder) throws {

      let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
      let texts: [String] = try container.decode([String].self, forKey: .allLinkDatabase)
      var records: [AllLinkRecord] = []

      for text in texts {

        guard let record = StoredBytes.record(text) else {

          throw DecodingError.dataCorruptedError(forKey: .allLinkDatabase, in: container, debugDescription: "Expected eight bytes.")

        }

        records.append(record)

      }

      self.allLinkDatabase = records

    }

    func encode(to encoder: any Encoder) throws {

      var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
      let texts: [String] = allLinkDatabase.map { (record: AllLinkRecord) -> String in StoredBytes.text(record: record) }

      try container.encode(texts, forKey: .allLinkDatabase)

    }

  }

  /// Where the Hub is: its host, port and Insteon ID, never its credentials.
  private struct StoredHub: Codable {

    private enum CodingKeys: String, CodingKey {

      case host
      case port
      case insteonID

    }

    var location: HubLocation

    init(_ location: HubLocation) {

      self.location = location

    }

    init(from decoder: any Decoder) throws {

      let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
      let host: String = try container.decode(String.self, forKey: .host)
      let port: Int = try container.decode(Int.self, forKey: .port)
      let insteonIDText: String? = try? container.decodeIfPresent(String.self, forKey: .insteonID)

      guard !host.isEmpty, (1...65_535).contains(port) else {

        throw DecodingError.dataCorruptedError(forKey: .port, in: container, debugDescription: "Expected a host and a port from 1 to 65535.")

      }

      location = HubLocation(host: host, port: port, insteonID: insteonIDText.flatMap { (text: String) -> InsteonAddress? in InsteonAddress(text) })

    }

    func encode(to encoder: any Encoder) throws {

      var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

      try container.encode(location.host, forKey: .host)
      try container.encode(location.port, forKey: .port)
      try container.encodeIfPresent(location.insteonID.map { (address: InsteonAddress) -> String in "\(address)" }, forKey: .insteonID)

    }

  }

  /// A value that decodes as `nil` rather than failing the whole file when it doesn't read.
  private struct Lenient<Value: Codable>: Codable {

    var value: Value?

    init(_ value: Value) {

      self.value = value

    }

    init(from decoder: any Decoder) throws {

      value = try? Value(from: decoder)

    }

    func encode(to encoder: any Encoder) throws {

      try value.encode(to: encoder)

    }

  }

}

/// How the file writes an engine: the Swift case's name, as the Insteon device catalog does.
private enum StoredEngine {

  static func name(of engine: InsteonEngine) -> String {

    switch engine {
    case .i1: "i1"
    case .i2: "i2"
    case .i2cs: "i2cs"
    }

  }

  static func engine(named name: String) -> InsteonEngine? {

    InsteonEngine.allCases.first { (engine: InsteonEngine) -> Bool in self.name(of: engine) == name }

  }

}

/// How the file writes bytes: `0x` and two uppercase hexadecimal digits for one byte, `0x` and
/// four for a record's address, and a record as eight space-separated pairs.
private enum StoredBytes {

  static func text(_ byte: UInt8) -> String {

    "0x" + digits(byte)

  }

  static func text(memoryAddress: UInt16) -> String {

    "0x" + digits(UInt8(memoryAddress >> 8)) + digits(UInt8(memoryAddress & 0xFF))

  }

  static func text(record: AllLinkRecord) -> String {

    record.bytes.map(digits(_:)).joined(separator: " ")

  }

  static func byte(_ text: String) -> UInt8? {

    guard text.count == 4, text.hasPrefix("0x") else {

      return nil

    }

    return pair(text.dropFirst(2))

  }

  static func memoryAddress(_ text: String) -> UInt16? {

    guard text.count == 6, text.hasPrefix("0x") else {

      return nil

    }

    let digits: Substring = text.dropFirst(2)

    guard let high = pair(digits.prefix(2)), let low = pair(digits.suffix(2)) else {

      return nil

    }

    return UInt16(high) << 8 | UInt16(low)

  }

  static func record(_ text: String) -> AllLinkRecord? {

    let pairs: [Substring] = text.split(separator: " ", omittingEmptySubsequences: false)

    guard pairs.count == 8 else {

      return nil

    }

    let bytes: [UInt8] = pairs.compactMap(pair(_:))

    guard bytes.count == 8 else {

      return nil

    }

    return AllLinkRecord(
      flags: AllLinkRecordFlags(rawValue: bytes[0]),
      group: AllLinkGroupNumber(rawValue: bytes[1]),
      address: InsteonAddress(bytes[2], bytes[3], bytes[4]),
      data1: bytes[5],
      data2: bytes[6],
      data3: bytes[7]
    )

  }

  private static func digits(_ byte: UInt8) -> String {

    let text: String = String(byte, radix: 16, uppercase: true)

    return byte < 0x10 ? "0" + text : text

  }

  /// Two hexadecimal digits as a byte, or `nil` if the text isn't two.
  private static func pair(_ text: Substring) -> UInt8? {

    guard text.count == 2, text.allSatisfy(\.isHexDigit) else {

      return nil

    }

    return UInt8(text, radix: 16)

  }

}

/// Why a ``JSONFileDeviceRegistryStore`` couldn't read or write its file.
///
/// The errors never include the file's devices or identities.
public enum DeviceRegistryStoreError: Error, Hashable, Sendable, CustomStringConvertible {

  /// Something other than a regular file is at the file's path, or the file couldn't be read.
  case unreadableFile

  /// The file isn't a registry file, such as one that isn't JSON or has no devices.
  case malformedContents

  /// The file is in a newer format than the store reads, with this version.
  case unsupportedVersion(Int)

  /// The file couldn't be written, with the system's error code, such as `EACCES` or `ENOSPC`.
  case writeFailed(code: Int32)

  /// The error as a sentence.
  public var description: String {

    switch self {
    case .unreadableFile:
      "The device registry file couldn't be read."
    case .malformedContents:
      "The device registry file isn't in a format the store reads, so it's left as it is."
    case let .unsupportedVersion(version):
      "The device registry file is in format \(version), newer than format \(JSONFileDeviceRegistryStore.formatVersion), which the store reads, so it's left as it is."
    case let .writeFailed(code):
      "The device registry file couldn't be written (error \(code))."
    }

  }

}
