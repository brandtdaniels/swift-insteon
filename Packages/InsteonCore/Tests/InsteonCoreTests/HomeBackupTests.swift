import Foundation
import InsteonProtocol
import Testing
@testable import InsteonCore

/// The backup file: what it holds, that it reads back as it was written, and that a change to it
/// is caught.
@Suite(.timeLimit(.minutes(1)))
struct HomeBackupTests {

  static let sample: HomeBackup = HomeBackup(
    createdAt: BackupExample.createdAt,
    source: .modem,
    modem: BackupModem(
      address: BackupExample.oldModem,
      identity: BackupIdentity(category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E),
      allLinkDatabase: [BackupExample.record(.controller, group: 1, BackupExample.lamp, data: [0x01, 0x02, 0x03])]
    ),
    devices: [
      BackupExample.device(BackupExample.plug, engine: .i2cs, name: "Porch"),
      BackupExample.device(BackupExample.lamp, engine: .i2),
      BackupExample.unreadable(BackupExample.sensor)
    ]
  )

  // MARK: - Writing and reading

  @Test func readsBackWhatItWrote() throws {

    let data: Data = try Self.sample.encoded()
    let restored: HomeBackup = try HomeBackup(parsing: data)

    #expect(restored == Self.sample)

  }

  @Test func writesTheSameBytesForTheSameBackup() throws {

    #expect(try Self.sample.encoded() == (try Self.sample.encoded()))

  }

  @Test func keepsDevicesInAddressOrder() {

    #expect(Self.sample.devices.map(\.address) == [BackupExample.sensor, BackupExample.lamp, BackupExample.plug])

  }

  @Test func writesTheFormatNumberAndTheTimeInUTC() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self)

    #expect(text.contains("\"format\" : 1"))
    #expect(text.contains("\"createdAt\" : \"2027-01-15T08:00:00Z\""))

  }

  @Test func writesRecordsAsReadableText() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self)

    #expect(text.contains("\"address\" : \"1A.2B.3C\""))
    #expect(text.contains("\"data\" : \"01 02 03\""))
    #expect(text.contains("\"memory\" : \"0x0FFF\""))
    #expect(text.contains("\"role\" : \"responder\""))

  }

  @Test func holdsNoDashCharacters() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self)

    #expect(!text.contains("\u{2014}"))
    #expect(!text.contains("\u{2013}"))

  }

  @Test func recordsWhyADeviceHasNoDatabase() throws {

    let restored: HomeBackup = try HomeBackup(parsing: Self.sample.encoded())

    #expect(restored.devices.first?.unreadable?.reason == .noAnswer)
    #expect(restored.devices.first?.allLinkDatabase == nil)

  }

  @Test func keepsTheServicesRulesAndRoutesAndCoversThemWithTheChecksum() throws {

    let rule: BackupValue = .object(["id": .string("front-door"), "includeDetail": .bool(true), "cooldownSeconds": .integer(60)])
    let route = BackupRoute(kind: "relay", ticket: "ticket-1")
    let backup: HomeBackup = Self.sample.including(notificationRules: [rule], routes: [route], schedules: [])
    let restored: HomeBackup = try HomeBackup(parsing: backup.encoded())

    #expect(restored.notificationRules == [rule])
    #expect(restored.routes == [route])
    #expect(restored.checksum != Self.sample.checksum)

  }

  @Test func keepsTheServicesSchedulesAndCoversThemWithTheChecksum() throws {

    let schedule: BackupValue = .object(["id": .string("porch"), "enabled": .bool(true)])
    let without: HomeBackup = Self.sample.including(notificationRules: [], routes: [], schedules: [])
    let backup: HomeBackup = Self.sample.including(notificationRules: [], routes: [], schedules: [schedule])
    let restored: HomeBackup = try HomeBackup(parsing: backup.encoded())

    #expect(Self.sample.schedules == nil)
    #expect(restored.schedules == [schedule])
    #expect(restored.checksum == backup.checksum)
    #expect(backup.checksum != without.checksum)

  }

  @Test func refusesAFileWhoseSchedulesChangedAfterItWasWritten() throws {

    let schedule: BackupValue = .object(["id": .string("porch")])
    let backup: HomeBackup = Self.sample.including(notificationRules: [], routes: [], schedules: [schedule])
    let text: String = String(decoding: try backup.encoded(), as: UTF8.self).replacingOccurrences(of: "\"porch\"", with: "\"garage\"")

    #expect(throws: HomeBackupError.checksumMismatch) { try HomeBackup(parsing: Data(text.utf8)) }

  }

  // MARK: - Checking

  @Test func carriesASha256ChecksumOfItsContents() {

    #expect(Self.sample.checksum.hasPrefix("sha256:"))
    #expect(Self.sample.checksum.count == 7 + 64)

  }

  @Test func refusesAFileWhoseContentsChanged() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self)
    let changed: Data = Data(text.replacingOccurrences(of: "\"01 02 03\"", with: "\"01 02 04\"").utf8)

    #expect(throws: HomeBackupError.checksumMismatch) { try HomeBackup(parsing: changed) }

    let check: HomeBackupCheck = try HomeBackup.check(changed)

    #expect(!check.checksumMatches)
    #expect(!check.isComplete)

  }

  @Test func refusesAFileWithNoChecksum() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self)
    let lines: [String] = text.components(separatedBy: "\n").filter { !$0.contains("\"checksum\"") }

    #expect(throws: HomeBackupError.notABackup("The file has no \"checksum\".")) { try HomeBackup(parsing: Data(lines.joined(separator: "\n").utf8)) }

  }

  @Test func ignoresAKeyItDoesNotKnowAndStillChecksIt() throws {

    // A later section, such as schedules, is an optional key a reader of this format ignores,
    // and the checksum still covers it.
    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self)
    let sealed = try #require(Self.reseal(text))

    let restored: HomeBackup = try HomeBackup(parsing: sealed)

    #expect(restored.devices == Self.sample.devices)

    let tampered: Data = Data(String(decoding: sealed, as: UTF8.self).replacingOccurrences(of: "\"dusk\"", with: "\"dawn\"").utf8)

    #expect(throws: HomeBackupError.checksumMismatch) { try HomeBackup(parsing: tampered) }

  }

  @Test func countsWhatTheFileHolds() throws {

    let check: HomeBackupCheck = try HomeBackup.check(Self.sample.encoded())

    #expect(check.checksumMatches)
    #expect(check.backup.devices.count == 3)
    #expect(check.readableDeviceCount == 2)
    #expect(check.modemRecordCount == 1)
    #expect(check.unreadableDevices.map(\.address) == [BackupExample.sensor])
    #expect(check.unreadableDevices.first?.unreadable.reason == .noAnswer)
    #expect(!check.isComplete)

  }

  @Test func callsAFileWholeWhenEveryDatabaseWasRead() throws {

    let whole: HomeBackup = BackupExample.backup([BackupExample.device(BackupExample.lamp)])
    let check: HomeBackupCheck = try HomeBackup.check(whole.encoded())

    #expect(check.isComplete)

  }

  @Test func listsADeviceWhoseDatabaseLacksItsEndAsIncomplete() throws {

    let partial: BackupDevice = BackupExample.device(BackupExample.lamp, records: [BackupExample.record(.responder, group: 1, BackupExample.oldModem, memory: 0x0FFF)])
    let check: HomeBackupCheck = try HomeBackup.check(BackupExample.backup([partial]).encoded())

    #expect(check.unreadableDevices.map(\.unreadable.reason) == [.incomplete])
    #expect(!check.isComplete)

  }

  // MARK: - Refusing what isn't a backup

  @Test func refusesATextThatIsNotJSON() {

    #expect(throws: HomeBackupError.notJSON) { try HomeBackup(parsing: Data("not json".utf8)) }

  }

  @Test func refusesJSONThatIsNotAnObject() {

    #expect(throws: HomeBackupError.self) { try HomeBackup(parsing: Data("[1, 2]".utf8)) }

  }

  @Test func refusesAFileWithNoFormat() {

    #expect(throws: HomeBackupError.self) { try HomeBackup(parsing: Data("{}".utf8)) }

  }

  @Test func refusesAFormatItDoesNotRead() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self).replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2")

    #expect(throws: HomeBackupError.unsupportedFormat(2)) { try HomeBackup(parsing: Data(text.utf8)) }

  }

  @Test func refusesARecordWhoseDataIsNotThreeBytes() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self).replacingOccurrences(of: "\"01 02 03\"", with: "\"01 02\"")

    #expect(throws: HomeBackupError.self) { try HomeBackup(parsing: Data(text.utf8)) }

  }

  @Test func refusesADeviceWithBothADatabaseAndAReason() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self)
    let both: String = text.replacingOccurrences(of: "\"unreadable\" : {", with: "\"allLinkDatabase\" : {\"delta\": 1, \"records\": []}, \"unreadable\" : {")

    #expect(throws: HomeBackupError.self) { try HomeBackup.check(Data(both.utf8)) }

  }

  @Test func refusesAnAddressThatIsNotOne() throws {

    let text: String = String(decoding: try Self.sample.encoded(), as: UTF8.self).replacingOccurrences(of: "\"1A.2B.3C\"", with: "\"1A.2B\"")

    #expect(throws: HomeBackupError.self) { try HomeBackup.check(Data(text.utf8)) }

  }

  /// The file with a `schedules` key added and its checksum made again.
  static func reseal(_ text: String) -> Data? {

    guard var object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {

      return nil

    }

    object["checksum"] = nil
    object["schedules"] = ["dusk"]

    guard let checksum = try? HomeBackup.checksum(ofCanonical: object) else {

      return nil

    }

    object["checksum"] = checksum

    return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

  }

}
