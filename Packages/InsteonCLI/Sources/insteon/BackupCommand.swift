import Foundation
import InsteonCLISupport
import InsteonCore

/// `insteon backup`: reads the modem's network, or a Hub Pro's device list, into a file. Every
/// request it sends is a read. The decisions are in InsteonCore's `HomeBackupReader` and
/// InsteonCLISupport's `HomeBackupText` and `BackupFile`; this connects and prints.
enum BackupCommand {

  /// Reads a modem's network and writes the backup.
  static func run(_ options: BackupOptions, modem: ModemSession, hub: HubLocation?, names: ProductNames, printsJSON: Bool) async throws {

    try await IdentityStore.withNetwork(modem: modem, hub: hub, names: names) { (cached: CachedNetwork) async throws -> Void in

      let backup: HomeBackup = try await HomeBackupReader.read(network: cached.network, createdAt: Date()) { (progress: BackupProgress) -> Void in

        if let line = HomeBackupText.line(for: progress) {

          Output.note(line)

        }

      }

      try finish(backup, options, printsJSON: printsJSON)

    }

  }

  /// Reads a Hub Pro's device list and writes the backup.
  static func run(_ options: BackupOptions, hubPro network: HubProNetwork, printsJSON: Bool) async throws {

    Output.note("Reading the Hub Pro's device list...")

    let backup: HomeBackup = try await HomeBackupReader.read(hubPro: network, createdAt: Date())

    try finish(backup, options, printsJSON: printsJSON)

  }

  /// Checks a backup file, which needs no modem.
  static func check(path: String, printsJSON: Bool) throws {

    let check: HomeBackupCheck = try HomeBackup.check(BackupFile.read(path))
    let report: HomeBackupText.Report = HomeBackupText.report(check, path: path)

    try print(report, lines: HomeBackupText.checked(report), printsJSON: printsJSON)

    guard check.checksumMatches else {

      throw CommandFailure(description: "\(path) doesn't match its checksum.")

    }

    guard check.isComplete else {

      throw IncompleteResult(description: "\(path) is a valid backup, but some devices, or the modem, have no whole ALL-Link database in it.")

    }

  }

  // MARK: - Writing

  private static func finish(_ backup: HomeBackup, _ options: BackupOptions, printsJSON: Bool) throws {

    // Control-C after the reading stops here, so a canceled run writes nothing.
    try Task.checkCancellation()

    let data: Data = try backup.encoded()

    try BackupFile.write(data, to: options.path, overwrites: options.overwrites)

    let check: HomeBackupCheck = try HomeBackup.check(data)
    let report: HomeBackupText.Report = HomeBackupText.report(check, path: options.path)

    try print(report, lines: HomeBackupText.written(report), printsJSON: printsJSON)

    guard check.isComplete else {

      throw IncompleteResult(description: "The backup is written, but \(report.unreadable.count) \(report.unreadable.count == 1 ? "device has" : "devices have") no whole ALL-Link database in it.")

    }

  }

  private static func print(_ report: HomeBackupText.Report, lines: [String], printsJSON: Bool) throws {

    if printsJSON {

      try Output.json(report)

      return

    }

    for line in lines {

      Output.line(line)

    }

  }

}
