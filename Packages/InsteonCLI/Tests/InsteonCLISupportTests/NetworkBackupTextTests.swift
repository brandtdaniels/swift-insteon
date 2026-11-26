import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// What `insteon backup` and `insteon backup --check` say.
struct NetworkBackupTextTests {

  static let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let plug = InsteonAddress(0x4D, 0x5E, 0x6F)
  static let modem = InsteonAddress(0x11, 0x22, 0x33)

  static func database() -> BackupDatabase {

    BackupDatabase(delta: 0x01, records: [BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FFF)])

  }

  static func backup(extra: [BackupDevice] = []) -> NetworkBackup {

    NetworkBackup(
      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      source: .modem,
      modem: BackupModem(address: modem, allLinkDatabase: [BackupRecord(state: .inUse, role: .controller, group: 1, address: lamp, data: [1, 2, 3])]),
      devices: [BackupDevice(address: lamp, name: "Porch", allLinkDatabase: database())] + extra
    )

  }

  static func report(_ backup: NetworkBackup, matches: Bool = true) -> NetworkBackupText.Report {

    NetworkBackupText.report(NetworkBackupCheck(backup: backup, checksumMatches: matches), path: "home.json")

  }

  @Test func saysWhatTheReaderIsDoing() {

    #expect(NetworkBackupText.line(for: .readingModem) == "Reading the modem's ALL-Link database...")
    #expect(NetworkBackupText.line(for: .readingDevice(Self.lamp, position: 2, total: 9)) == "Reading 1A.2B.3C (2 of 9)...")
    #expect(NetworkBackupText.line(for: .deviceUnreadable(Self.plug, BackupUnreadable(reason: .noAnswer))) == "4D.5E.6F didn't answer.")

  }

  @Test(arguments: [
    (BackupUnreadableReason.noAnswer, "didn't answer"),
    (.rejectedModem, "rejected the modem, as an i2CS device does until it's linked to it"),
    (.damagedRecords, "returned records that failed their checksum on two readings"),
    (.notCached, "has no ALL-Link database the service cached"),
    (.unavailableFromSource, "has no ALL-Link database to read from this source"),
    (.failed, "couldn't be read"),
    (.incomplete, "has a partial ALL-Link database")
  ]) func explainsEachReason(reason: BackupUnreadableReason, text: String) {

    #expect(NetworkBackupText.reason(BackupUnreadable(reason: reason)) == text)

  }

  @Test func addsTheDetailToTheReason() {

    #expect(NetworkBackupText.reason(BackupUnreadable(reason: .damagedRecords, detail: "1 of 3 records failed")) == "returned records that failed their checksum on two readings (1 of 3 records failed)")

  }

  @Test func reportsAWholeBackup() {

    let lines = NetworkBackupText.written(Self.report(Self.backup()))

    #expect(lines == [
      "Wrote home.json, readable only by you.",
      "Modem 11.22.33: 1 link in its ALL-Link database.",
      "Devices: 1, 1 with a whole ALL-Link database."
    ])

  }

  @Test func listsEachDeviceWithNoDatabaseAndWhy() {

    let backup = Self.backup(extra: [BackupDevice(address: Self.plug, name: "Basement", unreadable: BackupUnreadable(reason: .noAnswer))])
    let lines = NetworkBackupText.written(Self.report(backup))

    #expect(lines.contains("Devices: 2, 1 with a whole ALL-Link database."))
    #expect(lines.contains("1 device has no whole ALL-Link database in the backup:"))
    #expect(lines.contains("  4D.5E.6F (Basement) didn't answer"))

  }

  @Test func saysWhenTheBackupHoldsNoModemDatabase() {

    let backup = NetworkBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .hubPro, modem: BackupModem(address: Self.modem, unreadable: BackupUnreadable(reason: .unavailableFromSource)), devices: [])
    let lines = NetworkBackupText.checked(Self.report(backup))

    #expect(lines.contains("Modem 11.22.33: its ALL-Link database isn't in the backup."))
    #expect(lines.first == "home.json: a Hub Pro backup, format 1, taken 2027-01-15T08:00:00Z.")

  }

  @Test func checkSaysWhetherTheChecksumMatches() {

    #expect(NetworkBackupText.checked(Self.report(Self.backup()))[1] == "The checksum matches.")
    #expect(NetworkBackupText.checked(Self.report(Self.backup(), matches: false))[1].hasPrefix("The checksum does NOT match"))

  }

  @Test func countsRulesRoutesAndSchedulesWhenTheBackupHoldsThem() {

    let backup = Self.backup().including(notificationRules: [.object([:]), .object([:])], routes: [BackupRoute(kind: "relay", ticket: "t")], schedules: [.object([:]), .object([:]), .object([:])])
    let lines = NetworkBackupText.checked(Self.report(backup))

    #expect(lines.contains("Notification rules: 2."))
    #expect(lines.contains("Routes: 1."))
    #expect(lines.contains("Schedules: 3."))

  }

  @Test func printsTheReportAsJSONKeys() throws {

    let backup = Self.backup(extra: [BackupDevice(address: Self.plug, unreadable: BackupUnreadable(reason: .noAnswer))])
    let data = try JSONEncoder().encode(Self.report(backup))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["complete"] as? Bool == false)
    #expect(object["devices"] as? Int == 2)
    #expect(object["readableDevices"] as? Int == 1)
    #expect(object["modem"] as? String == "11.22.33")
    #expect((object["unreadable"] as? [[String: Any]])?.first?["reason"] as? String == "noAnswer")

  }

  @Test func holdsNoDashCharacters() {

    let backup = Self.backup(extra: [BackupDevice(address: Self.plug, unreadable: BackupUnreadable(reason: .rejectedModem))])
    let text = (NetworkBackupText.written(Self.report(backup)) + NetworkBackupText.checked(Self.report(backup))).joined(separator: "\n")

    #expect(!text.contains("\u{2014}"))
    #expect(!text.contains("\u{2013}"))

  }

}
