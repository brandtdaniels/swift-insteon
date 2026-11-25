import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// What `insteon transfer plan` prints for a plan.
struct TransferPlanTextTests {

  static let old = InsteonAddress(0x11, 0x22, 0x33)
  static let new = InsteonAddress(0x77, 0x88, 0x99)
  static let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let plug = InsteonAddress(0x4D, 0x5E, 0x6F)

  static func record(_ role: BackupRecordRole, group: UInt8, _ address: InsteonAddress, state: BackupRecordState = .inUse, memory: UInt16? = nil) -> BackupRecord {

    BackupRecord(state: state, role: role, group: group, address: address, data: [0xFF, 0x1F, 0x01], memoryAddress: memory)

  }

  static func plan(_ target: [BackupRecord] = [], _ choice: ExistingLinksChoice = .refuse) throws -> TransferPlan {

    let lamp = BackupDevice(
      address: Self.lamp,
      name: "Porch",
      type: "Example Dimmer",
      engine: .i2,
      allLinkDatabase: BackupDatabase(delta: 0x07, records: [record(.responder, group: 1, old, memory: 0x0FFF), record(.responder, group: 0, InsteonAddress(0, 0, 0), state: .end, memory: 0x0FF7)])
    )
    let plug = BackupDevice(address: Self.plug, engine: .i1, allLinkDatabase: BackupDatabase(delta: 0x01, records: [record(.responder, group: 1, old, memory: 0x0FFF), record(.responder, group: 0, InsteonAddress(0, 0, 0), state: .end, memory: 0x0FF7)]))
    let backup = HomeBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .modem, modem: BackupModem(address: old, allLinkDatabase: [record(.controller, group: 1, Self.lamp), record(.controller, group: 1, Self.plug)]), devices: [lamp, plug])

    return try TransferPlanner.plan(from: backup, to: TransferTarget(address: new, records: target), existingLinks: choice)

  }

  @Test func opensByNamingTheModemsAndSayingNothingIsWritten() throws {

    let lines = TransferPlanText.lines(try Self.plan())

    #expect(lines[0] == "Plan to move the devices in the backup from 11.22.33 to 77.88.99. It writes nothing.")
    #expect(lines[1].hasPrefix("Backup checksum: sha256:"))

  }

  @Test func groupsTheStepsPerDeviceEachWithItsEffectAndExactRecord() throws {

    let lines = TransferPlanText.lines(try Self.plan())

    #expect(lines.contains("The new modem, 77.88.99:"))
    #expect(lines.contains("  1. [link] Add to the new modem: controller, group 1, 1A.2B.3C, data FF 1F 01."))
    #expect(lines.contains("Device 1A.2B.3C (Porch, Example Dimmer), runs i2:"))
    #expect(lines.contains { $0.hasPrefix("  2. [readOnly] Read the ALL-Link database of 1A.2B.3C") })
    #expect(lines.contains("  3. [link] Rewrite the record at 0x0FFF of 1A.2B.3C to responder, group 1, 77.88.99, data FF 1F 01, replacing the one naming 11.22.33."))
    #expect(lines.contains("       writes: responder, group 1, 77.88.99, data FF 1F 01 at 0x0FFF"))
    #expect(lines.contains { $0.hasPrefix("  4. [readOnly] Read the record of 1A.2B.3C back") })

  }

  @Test func listsDevicesToLinkByHandInOrderWithTheLinksAndSteps() throws {

    let lines = TransferPlanText.lines(try Self.plan())

    #expect(lines.contains("Link by hand, in this order (1 device), after the steps above:"))
    #expect(lines.contains("  1. 4D.5E.6F: it runs i1, which has no remote writes to its ALL-Link database"))
    #expect(lines.contains("       link to make again: controller, group 1, 4D.5E.6F, data FF 1F 01"))
    #expect(lines.contains { $0.hasPrefix("       a. On the new modem, press and hold the SET button") })
    #expect(lines.contains { $0.hasPrefix("       b. On 4D.5E.6F, press and hold its SET button") })

  }

  @Test func closesWithACountOfTheStepsByEffectAndSaysNothingWasWritten() throws {

    let lines = TransferPlanText.lines(try Self.plan())

    #expect(lines.last == "4 steps (2 readOnly, 2 link) on 1 device, 1 device to link by hand. Nothing was written.")

  }

  @Test func warnsFirstAboutLinksTheNewModemHolds() throws {

    let lines = TransferPlanText.lines(try Self.plan([Self.record(.controller, group: 1, InsteonAddress(0x2A, 0x2B, 0x2C))], .replaceDatabase))

    #expect(lines.contains("Read this first:"))
    #expect(lines.contains { $0.hasPrefix("  * The new modem already holds 1 link. Replacing its database removes each one first, which is destructive") })
    #expect(lines.contains { $0.contains("[destructive] Remove the new modem's record") })
    #expect(lines.last?.contains("1 destructive") == true)

  }

  @Test func saysNothingAboutWarningsWhenThereAreNone() throws {

    #expect(!TransferPlanText.lines(try Self.plan()).contains("Read this first:"))

  }

  @Test func holdsNoDashCharacters() throws {

    let text = TransferPlanText.lines(try Self.plan([Self.record(.controller, group: 1, InsteonAddress(0x2A, 0x2B, 0x2C))], .merge)).joined(separator: "\n")

    #expect(!text.contains("\u{2014}"))
    #expect(!text.contains("\u{2013}"))

  }

}
