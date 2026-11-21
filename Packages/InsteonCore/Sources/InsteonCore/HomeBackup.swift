import Crypto
import Foundation
import InsteonProtocol

/// What a ``HomeBackup`` was taken from.
public enum BackupSourceKind: String, Codable, Hashable, Sendable {
  /// A modem or a Hub, read through its serial commands: the modem's ALL-Link database and each
  /// device's.
  case modem
  /// A Hub Pro, read through its HTTP interface: its device list only.
  case hubPro
  /// The service, from what it has cached: it sends nothing to hardware to make a backup.
  case service
}

/// A home's Insteon network in one JSON file a person can read: the modem's identity and
/// ALL-Link database, each device's ALL-Link database where it could be read and the reason where
/// it couldn't, the devices' names and types, and, when a service wrote it, the service's
/// notification rules, routes and schedules.
///
/// A backup never holds a Hub's user name or password, a client's token, the gateway's password
/// or the contents of an environment file. It holds addresses and what devices reported.
///
/// ```swift
/// let backup = try await HomeBackupReader.read(network: network, createdAt: Date())
/// try backup.encoded().write(to: url)
///
/// let restored = try HomeBackup(parsing: Data(contentsOf: url))
/// print(restored.devices.count, "devices")
/// ```
///
/// The file's `format` is a number that rises when a reader of an older number could misread the
/// file. A key a reader doesn't know is ignored, so a section added later, such as the
/// service's schedules, is an optional key and doesn't change the number. The `checksum` is the
/// SHA-256 of the file's JSON with the checksum left out, written with sorted keys and no
/// spacing, so a change to any part of the file shows.
public struct HomeBackup: Codable, Hashable, Sendable {

  /// The format this package writes and reads.
  public static let currentFormat: Int = 1

  /// The file's format number.
  public let format: Int

  /// When the backup was taken, to the second.
  public let createdAt: Date

  /// What the backup was taken from.
  public let source: BackupSourceKind

  /// The modem, or `nil` if the source doesn't say which modem it is.
  public let modem: BackupModem?

  /// The devices, in address order, each with its database or the reason it has none.
  public let devices: [BackupDevice]

  /// The service's notification rules, each as the service's API writes it, or `nil` when the
  /// source isn't a service.
  public let notificationRules: [BackupValue]?

  /// The routes transports registered with the service, or `nil` when the source isn't a
  /// service.
  public let routes: [BackupRoute]?

  /// The service's schedules, each as the schedules file writes it and without the time it runs
  /// next, or `nil` when the source isn't a service. Timers aren't kept: a timer is a countdown,
  /// not configuration.
  public let schedules: [BackupValue]?

  /// The SHA-256 of the file's JSON without this key, as `sha256:` and 64 hexadecimal digits.
  public let checksum: String

  /// Creates a backup and its checksum.
  ///
  /// - Parameters:
  ///   - createdAt: When the backup was taken. It's kept to the second.
  ///   - source: What the backup was taken from.
  ///   - modem: The modem, or `nil`.
  ///   - devices: The devices. They're put in address order.
  ///   - notificationRules: The service's rules, or `nil`. Defaults to `nil`.
  ///   - routes: The service's routes, or `nil`. Defaults to `nil`.
  ///   - schedules: The service's schedules, or `nil`. Defaults to `nil`.
  public init(
    createdAt: Date,
    source: BackupSourceKind,
    modem: BackupModem?,
    devices: [BackupDevice],
    notificationRules: [BackupValue]? = nil,
    routes: [BackupRoute]? = nil,
    schedules: [BackupValue]? = nil
  ) {

    self.format = Self.currentFormat
    self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
    self.source = source
    self.modem = modem
    self.devices = devices.sorted { (first: BackupDevice, second: BackupDevice) -> Bool in first.address.bytes.lexicographicallyPrecedes(second.address.bytes) }
    self.notificationRules = notificationRules
    self.routes = routes
    self.schedules = schedules
    self.checksum = Self.checksum(of: HomeBackupBody(format: format, createdAt: self.createdAt, source: source, modem: modem, devices: self.devices, notificationRules: notificationRules, routes: routes, schedules: schedules))

  }

  /// This backup with the service's notification rules, routes and schedules, and a checksum that
  /// covers them.
  ///
  /// - Parameters:
  ///   - notificationRules: The rules, each as the service's API writes it.
  ///   - routes: The routes.
  ///   - schedules: The schedules, each as the schedules file writes it.
  /// - Returns: The backup.
  public func including(notificationRules: [BackupValue], routes: [BackupRoute], schedules: [BackupValue]) -> HomeBackup {

    HomeBackup(createdAt: createdAt, source: source, modem: modem, devices: devices, notificationRules: notificationRules, routes: routes, schedules: schedules)

  }

  /// The file's contents: the JSON, indented, with sorted keys and a final newline.
  ///
  /// - Returns: The bytes to write.
  /// - Throws: An error from the encoder, which doesn't happen for a backup made by this package.
  public func encoded() throws -> Data {

    let encoder: JSONEncoder = Self.encoder(formatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

    return try encoder.encode(self) + Data("\n".utf8)

  }

  /// Reads a backup from a file's contents and checks it.
  ///
  /// - Parameter data: The file's contents.
  /// - Throws: ``HomeBackupError`` if the file isn't JSON, is of a format this package doesn't
  ///   read, isn't a backup, or doesn't match its checksum.
  public init(parsing data: Data) throws {

    let inspected: HomeBackupInspection = try Self.inspect(data)

    guard inspected.checksumMatches else {

      throw HomeBackupError.checksumMismatch

    }

    self = inspected.backup

  }

  /// Checks a file's contents without refusing a checksum that doesn't match, so a person can
  /// be told what the file holds and that it was changed.
  ///
  /// - Parameter data: The file's contents.
  /// - Returns: What the file holds.
  /// - Throws: ``HomeBackupError`` if the file isn't JSON, is of a format this package doesn't
  ///   read, or isn't a backup.
  public static func check(_ data: Data) throws -> HomeBackupCheck {

    let inspected: HomeBackupInspection = try inspect(data)

    return HomeBackupCheck(backup: inspected.backup, checksumMatches: inspected.checksumMatches)

  }

  // MARK: - Reading

  private static func inspect(_ data: Data) throws -> HomeBackupInspection {

    let object: Any

    do {

      object = try JSONSerialization.jsonObject(with: data)

    } catch {

      throw HomeBackupError.notJSON

    }

    guard var fields = object as? [String: Any] else {

      throw HomeBackupError.notABackup("The file's JSON isn't an object.")

    }

    guard let format = fields["format"] as? Int else {

      throw HomeBackupError.notABackup("The file has no format number.")

    }

    guard format >= 1, format <= currentFormat else {

      throw HomeBackupError.unsupportedFormat(format)

    }

    let declared: String? = fields["checksum"] as? String

    fields["checksum"] = nil

    let backup: HomeBackup

    do {

      backup = try decoder().decode(HomeBackup.self, from: data)

    } catch let error as DecodingError {

      throw HomeBackupError.notABackup(describe(error))

    }

    let actual: String? = try? checksum(ofCanonical: fields)

    return HomeBackupInspection(backup: backup, checksumMatches: declared != nil && declared == actual)

  }

  private static func describe(_ error: DecodingError) -> String {

    switch error {
    case let .keyNotFound(key, _):
      "The file has no \"\(key.stringValue)\"."
    case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
      context.codingPath.isEmpty ? context.debugDescription : "\(context.debugDescription) (at \(context.codingPath.map(\.stringValue).joined(separator: ".")))"
    @unknown default:
      "The file isn't a backup."
    }

  }

  // MARK: - Checksum

  private static func checksum(of body: HomeBackupBody) -> String {

    let encoder: JSONEncoder = encoder(formatting: [])

    guard let data = try? encoder.encode(body), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let value = try? checksum(ofCanonical: object) else {

      // A body this package built always encodes, so this is a checksum nothing matches.
      return "sha256:invalid"

    }

    return value

  }

  static func checksum(ofCanonical fields: [String: Any]) throws -> String {

    let canonical: Data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])

    return "sha256:" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()

  }

  private static func encoder(formatting: JSONEncoder.OutputFormatting) -> JSONEncoder {

    let encoder: JSONEncoder = JSONEncoder()

    encoder.outputFormatting = formatting
    encoder.dateEncodingStrategy = .custom { (date: Date, encoder: any Encoder) throws -> Void in

      var container = encoder.singleValueContainer()

      try container.encode(Self.timestamp(date))

    }

    return encoder

  }

  private static func decoder() -> JSONDecoder {

    let decoder: JSONDecoder = JSONDecoder()

    decoder.dateDecodingStrategy = .custom { (decoder: any Decoder) throws -> Date in

      let container = try decoder.singleValueContainer()
      let text: String = try container.decode(String.self)

      guard let date = Self.date(from: text) else {

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "The date isn't written as year-month-day, a T, then hours, minutes and seconds in UTC, with a Z.")

      }

      return date

    }

    return decoder

  }

  /// A time as `2026-11-20T18:30:00Z`.
  static func timestamp(_ date: Date) -> String {

    let formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    formatter.formatOptions = [.withInternetDateTime]

    return formatter.string(from: date)

  }

  private static func date(from text: String) -> Date? {

    let formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    formatter.formatOptions = [.withInternetDateTime]

    return formatter.date(from: text)

  }

}

/// The keys of a backup that its checksum covers.
private struct HomeBackupBody: Encodable {

  let format: Int
  let createdAt: Date
  let source: BackupSourceKind
  let modem: BackupModem?
  let devices: [BackupDevice]
  let notificationRules: [BackupValue]?
  let routes: [BackupRoute]?
  let schedules: [BackupValue]?

}

private struct HomeBackupInspection {

  let backup: HomeBackup
  let checksumMatches: Bool

}

/// Why a file isn't a backup this package can use.
public enum HomeBackupError: Error, Hashable, Sendable {
  /// The file isn't JSON.
  case notJSON
  /// The file is JSON that isn't a backup, with what's wrong.
  case notABackup(String)
  /// The file's format number is one this package doesn't read.
  case unsupportedFormat(Int)
  /// The file's checksum doesn't match its contents, so it was changed or damaged after it was
  /// written.
  case checksumMismatch
}

extension HomeBackupError: CustomStringConvertible, LocalizedError {

  /// A one-line explanation.
  public var description: String {

    switch self {
    case .notJSON:
      "The file isn't JSON, so it isn't a backup."
    case let .notABackup(reason):
      "The file isn't a backup: \(reason)"
    case let .unsupportedFormat(format):
      "The backup's format is \(format), and this version reads formats 1 through \(HomeBackup.currentFormat). Update insteon to read it."
    case .checksumMismatch:
      "The backup's checksum doesn't match its contents, so it was changed or damaged after it was written. Nothing was used from it."
    }

  }

  /// The same text as `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}

/// What a backup file holds, from ``HomeBackup/check(_:)``.
public struct HomeBackupCheck: Hashable, Sendable {

  /// A device whose ALL-Link database the backup doesn't hold, with why.
  public struct UnreadableDevice: Hashable, Sendable {

    /// The device's address.
    public var address: InsteonAddress

    /// Why the backup holds no complete database for it.
    public var unreadable: BackupUnreadable

  }

  /// The backup the file holds.
  public var backup: HomeBackup

  /// Whether the file's checksum matches its contents.
  public var checksumMatches: Bool

  /// Creates a check.
  ///
  /// - Parameters:
  ///   - backup: The backup.
  ///   - checksumMatches: Whether the file's checksum matches its contents.
  public init(backup: HomeBackup, checksumMatches: Bool) {

    self.backup = backup
    self.checksumMatches = checksumMatches

  }

  /// The devices that have no complete ALL-Link database, each with the reason, in address
  /// order.
  public var unreadableDevices: [UnreadableDevice] {

    backup.devices.compactMap { (device: BackupDevice) -> UnreadableDevice? in

      if let unreadable = device.unreadable {

        return UnreadableDevice(address: device.address, unreadable: unreadable)

      }

      if let database = device.allLinkDatabase, !database.isComplete {

        return UnreadableDevice(address: device.address, unreadable: BackupUnreadable(reason: .incomplete))

      }

      return nil

    }

  }

  /// How many devices have a complete ALL-Link database.
  public var readableDeviceCount: Int {

    backup.devices.count - unreadableDevices.count

  }

  /// How many records of the modem's database are in use, or `nil` if the backup holds none.
  public var modemRecordCount: Int? {

    backup.modem?.allLinkDatabase?.filter(\.isInUse).count

  }

  /// Whether the file is whole: its checksum matches, the modem's database was read, and every
  /// device's was.
  public var isComplete: Bool {

    checksumMatches && backup.modem?.allLinkDatabase != nil && unreadableDevices.isEmpty

  }

}
