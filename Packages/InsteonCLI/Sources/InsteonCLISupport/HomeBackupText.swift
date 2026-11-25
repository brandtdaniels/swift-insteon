import Foundation
import InsteonCore
import InsteonProtocol

/// What `insteon backup` and `insteon backup --check` print.
public enum HomeBackupText {

  /// The line of progress for a step of reading, for standard error, or `nil` for a step that
  /// needs no line of its own.
  ///
  /// - Parameter progress: What the reader is doing.
  /// - Returns: The line.
  public static func line(for progress: BackupProgress) -> String? {

    switch progress {
    case .readingModem:
      "Reading the modem's ALL-Link database..."
    case let .readingDevice(address, position, total):
      "Reading \(address) (\(position) of \(total))..."
    case let .deviceUnreadable(address, unreadable):
      "\(address) \(reason(unreadable))."
    }

  }

  /// The reason a device has no ALL-Link database in the backup, as a clause.
  ///
  /// - Parameter unreadable: The reason the backup records.
  /// - Returns: A clause such as "didn't answer".
  public static func reason(_ unreadable: BackupUnreadable) -> String {

    let text: String = switch unreadable.reason {
    case .noAnswer: "didn't answer"
    case .rejectedModem: "rejected the modem, as an i2CS device does until it's linked to it"
    case .damagedRecords: "returned records that failed their checksum on two readings"
    case .notCached: "has no ALL-Link database the service cached"
    case .unavailableFromSource: "has no ALL-Link database to read from this source"
    case .failed: "couldn't be read"
    case .incomplete: "has a partial ALL-Link database"
    }

    return unreadable.detail.map { "\(text) (\($0))" } ?? text

  }

  /// What a backup file holds, as `--json` prints it.
  public struct Report: Encodable, Hashable, Sendable {

    /// A device without a complete ALL-Link database.
    public struct Unreadable: Encodable, Hashable, Sendable {
      /// The device's address.
      public var address: String
      /// The device's name, if the backup has one.
      public var name: String?
      /// Why there is no database.
      public var reason: String
      /// A short note, if the backup has one.
      public var detail: String?
    }

    /// The file.
    public var file: String
    /// The backup's format number.
    public var format: Int
    /// What the backup was taken from.
    public var source: String
    /// When it was taken, in UTC.
    public var createdAt: String
    /// Whether the checksum matches, or `nil` for a backup this command just wrote.
    public var checksumMatches: Bool?
    /// Whether every database was read and the checksum matches.
    public var complete: Bool
    /// The modem's address, if the backup has one.
    public var modem: String?
    /// How many links the modem's database holds, if it was read.
    public var modemLinks: Int?
    /// How many devices the backup lists.
    public var devices: Int
    /// How many have a whole ALL-Link database.
    public var readableDevices: Int
    /// The devices without one.
    public var unreadable: [Unreadable]
    /// How many notification rules the backup holds, if it holds any.
    public var notificationRules: Int?
    /// How many routes the backup holds, if it holds any.
    public var routes: Int?
    /// How many schedules the backup holds, if it holds any.
    public var schedules: Int?

  }

  /// The report for a backup.
  ///
  /// - Parameters:
  ///   - check: What the file holds.
  ///   - path: The file.
  /// - Returns: The report.
  public static func report(_ check: HomeBackupCheck, path: String) -> Report {

    let backup: HomeBackup = check.backup
    let names: [InsteonAddress: String] = Dictionary(backup.devices.compactMap { (device: BackupDevice) -> (InsteonAddress, String)? in device.name.map { (device.address, $0) } }, uniquingKeysWith: { first, _ in first })

    return Report(
      file: path,
      format: backup.format,
      source: backup.source.rawValue,
      createdAt: timestamp(backup.createdAt),
      checksumMatches: check.checksumMatches,
      complete: check.isComplete,
      modem: backup.modem.map { "\($0.address)" },
      modemLinks: check.modemRecordCount,
      devices: backup.devices.count,
      readableDevices: check.readableDeviceCount,
      unreadable: check.unreadableDevices.map { (device: HomeBackupCheck.UnreadableDevice) -> Report.Unreadable in
        Report.Unreadable(address: "\(device.address)", name: names[device.address], reason: device.unreadable.reason.rawValue, detail: device.unreadable.detail)
      },
      notificationRules: backup.notificationRules?.count,
      routes: backup.routes?.count,
      schedules: backup.schedules?.count
    )

  }

  /// The lines `insteon backup` prints after it wrote a backup.
  ///
  /// - Parameters:
  ///   - report: What the file holds.
  /// - Returns: The lines, for standard output.
  public static func written(_ report: Report) -> [String] {

    var lines: [String] = ["Wrote \(report.file), readable only by you."]

    lines.append(contentsOf: counts(report))
    lines.append(contentsOf: unreadable(report))

    return lines

  }

  /// The lines `insteon backup --check` prints.
  ///
  /// - Parameter report: What the file holds.
  /// - Returns: The lines, for standard output.
  public static func checked(_ report: Report) -> [String] {

    var lines: [String] = [
      "\(report.file): a \(source(report.source)) backup, format \(report.format), taken \(report.createdAt).",
      report.checksumMatches == true ? "The checksum matches." : "The checksum does NOT match: the file was changed or damaged after it was written, so don't use it."
    ]

    lines.append(contentsOf: counts(report))
    lines.append(contentsOf: unreadable(report))

    return lines

  }

  private static func counts(_ report: Report) -> [String] {

    var lines: [String] = []

    if let modem = report.modem {

      lines.append(report.modemLinks.map { "Modem \(modem): \($0) \($0 == 1 ? "link" : "links") in its ALL-Link database." } ?? "Modem \(modem): its ALL-Link database isn't in the backup.")

    } else {

      lines.append("The backup doesn't say which modem it was taken from.")

    }

    lines.append("Devices: \(report.devices), \(report.readableDevices) with a whole ALL-Link database.")

    if let rules = report.notificationRules {

      lines.append("Notification rules: \(rules).")

    }

    if let routes = report.routes {

      lines.append("Routes: \(routes).")

    }

    if let schedules = report.schedules {

      lines.append("Schedules: \(schedules).")

    }

    return lines

  }

  private static func unreadable(_ report: Report) -> [String] {

    guard !report.unreadable.isEmpty else {

      return []

    }

    var lines: [String] = ["\(report.unreadable.count) \(report.unreadable.count == 1 ? "device has" : "devices have") no whole ALL-Link database in the backup:"]

    for device in report.unreadable {

      let name: String = device.name.map { " (\($0))" } ?? ""
      let unreadable: BackupUnreadable = BackupUnreadable(reason: BackupUnreadableReason(rawValue: device.reason) ?? .failed, detail: device.detail)

      lines.append("  \(device.address)\(name) \(reason(unreadable))")

    }

    return lines

  }

  private static func source(_ kind: String) -> String {

    switch kind {
    case "hubPro":
      "Hub Pro"
    case "service":
      "service"
    default:
      "modem"
    }

  }

  private static func timestamp(_ date: Date) -> String {

    let formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    formatter.formatOptions = [.withInternetDateTime]

    return formatter.string(from: date)

  }

}
