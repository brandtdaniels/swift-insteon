import Foundation
import InsteonLinking
import InsteonProtocol

/// The state of an ALL-Link database record in a ``NetworkBackup``.
public enum BackupRecordState: String, Codable, Hashable, Sendable {
  /// The record holds a link.
  case inUse
  /// The record was a link once and is free to be written again.
  case free
  /// The record marks the end of a device's database: one that has never been used.
  case end
}

/// Whether a record's owner controls the group or responds to it.
public enum BackupRecordRole: String, Codable, Hashable, Sendable {
  /// The owner controls the group, and the other device responds to it.
  case controller
  /// The owner responds to the other device's group.
  case responder
}

/// One record of an ALL-Link database, as a ``NetworkBackup`` keeps it.
///
/// In the file a record reads as `{"address": "1A.2B.3C", "data": "FF 1F 01", "group": 1,
/// "memory": "0x0FF7", "role": "responder", "state": "inUse"}`. The `memory` key is the record's
/// place in a device's database, and a record of the modem's has none.
public struct BackupRecord: Codable, Hashable, Sendable {

  /// Whether the record holds a link, is free, or marks the end of the database.
  public var state: BackupRecordState

  /// Whether the database's owner controls the group or responds to it.
  public var role: BackupRecordRole

  /// The group: the owner's own group in a controller record, and the other device's in a
  /// responder record.
  public var group: UInt8

  /// The other device in the link.
  public var address: InsteonAddress

  /// The record's three data bytes.
  public var data: [UInt8]

  /// Where the record is in a device's database, or `nil` for a record of the modem's.
  public var memoryAddress: UInt16?

  /// Creates a record.
  ///
  /// - Parameters:
  ///   - state: Whether the record holds a link.
  ///   - role: Whether the owner controls the group.
  ///   - group: The group.
  ///   - address: The other device in the link.
  ///   - data: The three data bytes.
  ///   - memoryAddress: Where the record is in a device's database. Defaults to `nil`.
  public init(state: BackupRecordState, role: BackupRecordRole, group: UInt8, address: InsteonAddress, data: [UInt8], memoryAddress: UInt16? = nil) {

    self.state = state
    self.role = role
    self.group = group
    self.address = address
    self.data = data
    self.memoryAddress = memoryAddress

  }

  /// The record a database held, as the backup keeps it.
  ///
  /// - Parameter record: A record of the modem's or of a device's.
  public init(_ record: LinkRecord) {

    self.init(
      state: record.isEndOfDatabase ? .end : (record.isInUse ? .inUse : .free),
      role: record.isController ? .controller : .responder,
      group: record.group.rawValue,
      address: record.address,
      data: Array((record.data + [0x00, 0x00, 0x00]).prefix(3)),
      memoryAddress: record.memoryAddress
    )

  }

  /// Whether the record holds a link.
  public var isInUse: Bool {

    state == .inUse

  }

  private enum Keys: String, CodingKey {

    case state, role, group, address, data, memory

  }

  /// Reads a record from a backup.
  ///
  /// - Throws: `DecodingError` if the address, the data bytes or the memory address aren't
  ///   written as the file writes them.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: Keys.self)

    state = try container.decode(BackupRecordState.self, forKey: .state)
    role = try container.decode(BackupRecordRole.self, forKey: .role)
    group = try container.decode(UInt8.self, forKey: .group)
    address = try BackupText.address(in: container, forKey: .address)

    let bytes: String = try container.decode(String.self, forKey: .data)

    guard let parsed = BackupText.bytes(bytes), parsed.count == 3 else {

      throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "The data isn't three bytes written as pairs of hexadecimal digits.")

    }

    data = parsed

    if let memory = try container.decodeIfPresent(String.self, forKey: .memory) {

      guard let parsed = BackupText.memoryAddress(memory) else {

        throw DecodingError.dataCorruptedError(forKey: .memory, in: container, debugDescription: "The memory address isn't written as 0x and four hexadecimal digits.")

      }

      memoryAddress = parsed

    } else {

      memoryAddress = nil

    }

  }

  /// Writes the record as the file keeps it.
  public func encode(to encoder: any Encoder) throws {

    var container = encoder.container(keyedBy: Keys.self)

    try container.encode(state, forKey: .state)
    try container.encode(role, forKey: .role)
    try container.encode(group, forKey: .group)
    try container.encode("\(address)", forKey: .address)
    try container.encode(BackupText.pairs(data), forKey: .data)
    try container.encodeIfPresent(memoryAddress.map(BackupText.memory), forKey: .memory)

  }

}

/// Why a device or the modem has no ALL-Link database in a ``NetworkBackup``.
public enum BackupUnreadableReason: String, Codable, Hashable, Sendable {
  /// The device didn't answer.
  case noAnswer
  /// The device rejected the modem, as an i2CS device does until it's linked to it.
  case rejectedModem
  /// Records failed their checksum on each of two readings, so what they hold can't be trusted.
  case damagedRecords
  /// The service holds no copy of the database: none was read, or the source sends nothing to make one.
  case notCached
  /// The source doesn't give out ALL-Link databases, as a Hub Pro doesn't.
  case unavailableFromSource
  /// The modem didn't confirm sending the request, so the device was never asked and the modem is
  /// still busy with it.
  case modemStoppedEchoing
  /// The Hub stopped answering while it was reachable before, as it does for a device on a marginal
  /// powerline signal.
  case hubStoppedAnswering
  /// The reading failed for another reason.
  case failed
  /// The database ended without the record that marks its end, so part of it is missing.
  case incomplete
}

/// An ALL-Link database a backup couldn't hold, with the reason.
public struct BackupUnreadable: Codable, Hashable, Sendable {

  /// Why there is no database.
  public var reason: BackupUnreadableReason

  /// A short note that holds no address or credential, such as how many records were damaged,
  /// or `nil`.
  public var detail: String?

  /// Creates an entry.
  ///
  /// - Parameters:
  ///   - reason: Why there is no database.
  ///   - detail: A short note, or `nil`.
  public init(reason: BackupUnreadableReason, detail: String? = nil) {

    self.reason = reason
    self.detail = detail

  }

}

/// A device's ALL-Link database as a backup keeps it.
public struct BackupDatabase: Codable, Hashable, Sendable {

  /// The delta the device reported when its database was read.
  public var delta: UInt8

  /// The records in the device's order, ending with the record that marks the end of the
  /// database when the whole database was read.
  public var records: [BackupRecord]

  /// Creates a database.
  ///
  /// - Parameters:
  ///   - delta: The delta the database was read at.
  ///   - records: The records in the device's order.
  public init(delta: UInt8, records: [BackupRecord]) {

    self.delta = delta
    self.records = records

  }

  /// Whether the database ends with the record that marks its end, so no record is missing
  /// after the last one read.
  public var isComplete: Bool {

    records.last?.state == .end

  }

}

/// The engine a device runs, as a backup keeps it.
public enum BackupEngine: String, Codable, Hashable, Sendable {
  /// An i1 device.
  case i1
  /// An i2 device.
  case i2
  /// An i2CS device.
  case i2cs

  /// The engine the protocol names.
  ///
  /// - Parameter engine: The engine.
  public init(_ engine: InsteonEngine) {

    switch engine {
    case .i1:
      self = .i1
    case .i2:
      self = .i2
    case .i2cs:
      self = .i2cs
    }

  }

}

/// The category, subcategory and firmware version a device reported, as a backup keeps them:
/// each as `0x` and two hexadecimal digits.
public struct BackupIdentity: Codable, Hashable, Sendable {

  /// The category.
  public var category: UInt8

  /// The subcategory.
  public var subcategory: UInt8

  /// The firmware version, or `nil` if it isn't known.
  public var firmwareVersion: UInt8?

  /// Creates an identity.
  ///
  /// - Parameters:
  ///   - category: The category.
  ///   - subcategory: The subcategory.
  ///   - firmwareVersion: The firmware version, or `nil`. Defaults to `nil`.
  public init(category: UInt8, subcategory: UInt8, firmwareVersion: UInt8? = nil) {

    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// The identity a device reported.
  ///
  /// - Parameter identity: What the device reported.
  public init(_ identity: ReportedIdentity) {

    self.init(category: identity.category.rawValue, subcategory: identity.subcategory.rawValue, firmwareVersion: identity.firmwareVersion?.rawValue)

  }

  private enum Keys: String, CodingKey {

    case category, subcategory, firmwareVersion

  }

  /// Reads an identity from a backup.
  ///
  /// - Throws: `DecodingError` if a byte isn't written as `0x` and two hexadecimal digits.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: Keys.self)

    category = try BackupText.byte(in: container, forKey: .category)
    subcategory = try BackupText.byte(in: container, forKey: .subcategory)
    firmwareVersion = try container.contains(.firmwareVersion) ? BackupText.byte(in: container, forKey: .firmwareVersion) : nil

  }

  /// Writes the identity as the file keeps it.
  public func encode(to encoder: any Encoder) throws {

    var container = encoder.container(keyedBy: Keys.self)

    try container.encode(BackupText.byte(category), forKey: .category)
    try container.encode(BackupText.byte(subcategory), forKey: .subcategory)
    try container.encodeIfPresent(firmwareVersion.map(BackupText.byte), forKey: .firmwareVersion)

  }

}

/// A device a ``NetworkBackup`` holds: who it is, and its ALL-Link database or why there isn't one.
public struct BackupDevice: Codable, Hashable, Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The name a person or the Hub gave the device, or `nil` if there is none.
  public var name: String?

  /// What the device is: the product's name from the Insteon device catalog, or the type the
  /// Hub Pro lists, or `nil` if neither is known.
  public var type: String?

  /// The identity the device reported, or `nil` if it reported none.
  public var identity: BackupIdentity?

  /// The engine the device runs, or `nil` if it isn't known.
  public var engine: BackupEngine?

  /// The device's ALL-Link database, or `nil` when ``unreadable`` says why there is none.
  public var allLinkDatabase: BackupDatabase?

  /// Why there is no ALL-Link database, or `nil` when there is one.
  public var unreadable: BackupUnreadable?

  /// Creates a device with an ALL-Link database.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - name: The device's name, or `nil`.
  ///   - type: What the device is, or `nil`.
  ///   - identity: The identity it reported, or `nil`.
  ///   - engine: The engine it runs, or `nil`.
  ///   - allLinkDatabase: Its ALL-Link database.
  public init(address: InsteonAddress, name: String? = nil, type: String? = nil, identity: BackupIdentity? = nil, engine: BackupEngine? = nil, allLinkDatabase: BackupDatabase) {

    self.address = address
    self.name = name
    self.type = type
    self.identity = identity
    self.engine = engine
    self.allLinkDatabase = allLinkDatabase
    self.unreadable = nil

  }

  /// Creates a device with no ALL-Link database.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - name: The device's name, or `nil`.
  ///   - type: What the device is, or `nil`.
  ///   - identity: The identity it reported, or `nil`.
  ///   - engine: The engine it runs, or `nil`.
  ///   - unreadable: Why there is no database.
  public init(address: InsteonAddress, name: String? = nil, type: String? = nil, identity: BackupIdentity? = nil, engine: BackupEngine? = nil, unreadable: BackupUnreadable) {

    self.address = address
    self.name = name
    self.type = type
    self.identity = identity
    self.engine = engine
    self.allLinkDatabase = nil
    self.unreadable = unreadable

  }

  private enum Keys: String, CodingKey {

    case address, name, type, identity, engine, allLinkDatabase, unreadable

  }

  /// Reads a device from a backup.
  ///
  /// - Throws: `DecodingError` if the address isn't one, or if the device has both a database
  ///   and a reason for having none, or neither.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: Keys.self)

    address = try BackupText.address(in: container, forKey: .address)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    identity = try container.decodeIfPresent(BackupIdentity.self, forKey: .identity)
    engine = try container.decodeIfPresent(BackupEngine.self, forKey: .engine)
    allLinkDatabase = try container.decodeIfPresent(BackupDatabase.self, forKey: .allLinkDatabase)
    unreadable = try container.decodeIfPresent(BackupUnreadable.self, forKey: .unreadable)

    guard (allLinkDatabase == nil) != (unreadable == nil) else {

      throw DecodingError.dataCorruptedError(forKey: .unreadable, in: container, debugDescription: "A device has an ALL-Link database or a reason for having none, and not both.")

    }

  }

  /// Writes the device as the file keeps it.
  public func encode(to encoder: any Encoder) throws {

    var container = encoder.container(keyedBy: Keys.self)

    try container.encode("\(address)", forKey: .address)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encodeIfPresent(type, forKey: .type)
    try container.encodeIfPresent(identity, forKey: .identity)
    try container.encodeIfPresent(engine, forKey: .engine)
    try container.encodeIfPresent(allLinkDatabase, forKey: .allLinkDatabase)
    try container.encodeIfPresent(unreadable, forKey: .unreadable)

  }

}

/// The modem a ``NetworkBackup`` was taken from: its address, identity and ALL-Link database.
public struct BackupModem: Codable, Hashable, Sendable {

  /// The modem's address, which every device's records of its links to the modem name.
  public var address: InsteonAddress

  /// The identity the modem reported, or `nil` if the source doesn't give it.
  public var identity: BackupIdentity?

  /// The modem's records, or `nil` when ``unreadable`` says why there are none.
  public var allLinkDatabase: [BackupRecord]?

  /// Why there is no ALL-Link database, or `nil` when there is one.
  public var unreadable: BackupUnreadable?

  /// Creates a modem with its ALL-Link database.
  ///
  /// - Parameters:
  ///   - address: The modem's address.
  ///   - identity: The identity it reported, or `nil`.
  ///   - allLinkDatabase: Its records.
  public init(address: InsteonAddress, identity: BackupIdentity? = nil, allLinkDatabase: [BackupRecord]) {

    self.address = address
    self.identity = identity
    self.allLinkDatabase = allLinkDatabase
    self.unreadable = nil

  }

  /// Creates a modem with no ALL-Link database.
  ///
  /// - Parameters:
  ///   - address: The modem's address.
  ///   - identity: The identity it reported, or `nil`.
  ///   - unreadable: Why there is no database.
  public init(address: InsteonAddress, identity: BackupIdentity? = nil, unreadable: BackupUnreadable) {

    self.address = address
    self.identity = identity
    self.allLinkDatabase = nil
    self.unreadable = unreadable

  }

  private enum Keys: String, CodingKey {

    case address, identity, allLinkDatabase, unreadable

  }

  /// Reads a modem from a backup.
  ///
  /// - Throws: `DecodingError` if the address isn't one, or if the modem has both a database
  ///   and a reason for having none, or neither.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: Keys.self)

    address = try BackupText.address(in: container, forKey: .address)
    identity = try container.decodeIfPresent(BackupIdentity.self, forKey: .identity)
    allLinkDatabase = try container.decodeIfPresent([BackupRecord].self, forKey: .allLinkDatabase)
    unreadable = try container.decodeIfPresent(BackupUnreadable.self, forKey: .unreadable)

    guard (allLinkDatabase == nil) != (unreadable == nil) else {

      throw DecodingError.dataCorruptedError(forKey: .unreadable, in: container, debugDescription: "The modem has an ALL-Link database or a reason for having none, and not both.")

    }

  }

  /// Writes the modem as the file keeps it.
  public func encode(to encoder: any Encoder) throws {

    var container = encoder.container(keyedBy: Keys.self)

    try container.encode("\(address)", forKey: .address)
    try container.encodeIfPresent(identity, forKey: .identity)
    try container.encodeIfPresent(allLinkDatabase, forKey: .allLinkDatabase)
    try container.encodeIfPresent(unreadable, forKey: .unreadable)

  }

}

/// A route a transport registered with the service, as a backup keeps it. A ticket is a locator
/// only its transport reads, never a secret.
public struct BackupRoute: Codable, Hashable, Sendable {

  /// The transport's identifier.
  public var kind: String

  /// What the transport needs to reach the service.
  public var ticket: String

  /// Creates a route.
  ///
  /// - Parameters:
  ///   - kind: The transport's identifier.
  ///   - ticket: The transport's locator.
  public init(kind: String, ticket: String) {

    self.kind = kind
    self.ticket = ticket

  }

}

/// A JSON value, for the parts of a backup whose shape another package owns, such as the
/// service's notification rules.
public enum BackupValue: Codable, Hashable, Sendable {
  /// `null`.
  case null
  /// `true` or `false`.
  case bool(Bool)
  /// A whole number.
  case integer(Int)
  /// Text.
  case string(String)
  /// A list.
  case array([BackupValue])
  /// An object.
  case object([String: BackupValue])

  /// Reads any JSON value that holds no fractional number.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.singleValueContainer()

    if container.decodeNil() {

      self = .null

    } else if let value = try? container.decode(Bool.self) {

      self = .bool(value)

    } else if let value = try? container.decode(Int.self) {

      self = .integer(value)

    } else if let value = try? container.decode(String.self) {

      self = .string(value)

    } else if let value = try? container.decode([BackupValue].self) {

      self = .array(value)

    } else {

      self = .object(try container.decode([String: BackupValue].self))

    }

  }

  /// Writes the value as JSON.
  public func encode(to encoder: any Encoder) throws {

    var container = encoder.singleValueContainer()

    switch self {
    case .null:
      try container.encodeNil()
    case let .bool(value):
      try container.encode(value)
    case let .integer(value):
      try container.encode(value)
    case let .string(value):
      try container.encode(value)
    case let .array(value):
      try container.encode(value)
    case let .object(value):
      try container.encode(value)
    }

  }

}

/// How a backup writes bytes, addresses and memory addresses as text.
enum BackupText {

  static func pairs(_ bytes: [UInt8]) -> String {

    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")

  }

  static func byte(_ value: UInt8) -> String {

    String(format: "0x%02X", value)

  }

  static func memory(_ value: UInt16) -> String {

    String(format: "0x%04X", value)

  }

  static func bytes(_ text: String) -> [UInt8]? {

    let pairs: [Substring] = text.split(separator: " ", omittingEmptySubsequences: false)

    var bytes: [UInt8] = []

    for pair in pairs {

      guard pair.count == 2, pair.allSatisfy(\.isHexDigit), let value = UInt8(pair, radix: 16) else {

        return nil

      }

      bytes.append(value)

    }

    return bytes

  }

  static func memoryAddress(_ text: String) -> UInt16? {

    guard text.hasPrefix("0x"), text.count == 6, text.dropFirst(2).allSatisfy(\.isHexDigit) else {

      return nil

    }

    return UInt16(text.dropFirst(2), radix: 16)

  }

  static func address<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> InsteonAddress {

    let text: String = try container.decode(String.self, forKey: key)

    guard text.count == 8, let address = InsteonAddress(text) else {

      throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "The address isn't written as three pairs of hexadecimal digits separated by periods.")

    }

    return address

  }

  static func byte<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> UInt8 {

    let text: String = try container.decode(String.self, forKey: key)

    guard text.hasPrefix("0x"), text.count == 4, text.dropFirst(2).allSatisfy(\.isHexDigit), let value = UInt8(text.dropFirst(2), radix: 16) else {

      throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "The byte isn't written as 0x and two hexadecimal digits.")

    }

    return value

  }

}
