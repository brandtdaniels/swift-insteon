import Foundation
import InsteonHubPro
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport
import Testing
@testable import InsteonCore

/// What moving a backup's devices to a new modem takes, planned from the backup alone.
@Suite(.timeLimit(.minutes(1)))
struct TransferPlannerTests {

  typealias Example = BackupExample

  static let old = Example.oldModem
  static let new = Example.newModem

  static func target(_ records: [BackupRecord]? = []) -> TransferTarget {

    TransferTarget(address: new, records: records)

  }

  static func plan(_ backup: HomeBackup, _ records: [BackupRecord]? = [], _ choice: ExistingLinksChoice = .refuse) throws -> TransferPlan {

    try TransferPlanner.plan(from: backup, to: target(records), existingLinks: choice)

  }

  /// A device whose one responder record at 0x0FFF names the old modem, as the old modem's
  /// controller record for the device says.
  static func linked(_ address: InsteonAddress, engine: BackupEngine? = .i2) -> BackupDevice {

    Example.device(address, engine: engine)

  }

  // MARK: - The controller swap

  @Test func rewritesAResponderRecordNamingTheOldModemToNameTheNewOne() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)], modemRecords: [Example.record(.controller, group: 1, Example.lamp, data: [0x01, 0x02, 0x03])]))
    let device = try #require(plan.devices.first)
    let rewrite = try #require(device.steps.first { $0.action == .rewriteRecord })

    #expect(rewrite.effect == .link)
    #expect(rewrite.target == Example.lamp)
    #expect(rewrite.record == Example.record(.responder, group: 1, Self.new, data: [0xFF, 0x1F, 0x01], memory: 0x0FFF))
    #expect(rewrite.replaces == Example.record(.responder, group: 1, Self.old, data: [0xFF, 0x1F, 0x01], memory: 0x0FFF))

  }

  @Test func addsTheOldModemsControllerRecordToTheNewModem() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)], modemRecords: [Example.record(.controller, group: 1, Example.lamp, data: [0x01, 0x02, 0x03])]))
    let add = try #require(plan.modemSteps.first)

    #expect(plan.modemSteps.count == 1)
    #expect(add.action == .addModemRecord)
    #expect(add.effect == .link)
    #expect(add.target == Self.new)
    #expect(add.record == Example.record(.controller, group: 1, Example.lamp, data: [0x01, 0x02, 0x03]))

  }

  @Test func swapsADevicesControllerRecordAndAddsTheModemsResponderRecord() throws {

    // The device controls group 3 and the old modem responds to it.
    let device: BackupDevice = Example.device(Example.sensor, records: [Example.record(.controller, group: 3, Self.old, data: [0x00, 0x00, 0x03], memory: 0x0FFF), Example.end(0x0FF7)])
    let plan = try Self.plan(Example.backup([device], modemRecords: [Example.record(.responder, group: 3, Example.sensor, data: [0x00, 0x00, 0x03])]))
    let rewrite = try #require(plan.devices.first?.steps.first { $0.action == .rewriteRecord })

    #expect(rewrite.record == Example.record(.controller, group: 3, Self.new, data: [0x00, 0x00, 0x03], memory: 0x0FFF))
    #expect(plan.modemSteps.map(\.record) == [Example.record(.responder, group: 3, Example.sensor, data: [0x00, 0x00, 0x03])])

  }

  @Test func rewritesEveryRecordNamingTheOldModemInTheOrderOfTheirMemoryAddresses() throws {

    let records: [BackupRecord] = [
      Example.record(.responder, group: 2, Self.old, memory: 0x0FEF),
      Example.record(.responder, group: 1, Self.old, memory: 0x0FFF),
      Example.end(0x0FE7)
    ]
    let modem: [BackupRecord] = [Example.record(.controller, group: 1, Example.lamp), Example.record(.controller, group: 2, Example.lamp)]
    let plan = try Self.plan(Example.backup([Example.device(Example.lamp, records: records)], modemRecords: modem))

    #expect(plan.devices.first?.steps.compactMap(\.record?.memoryAddress) == [0x0FEF, 0x0FFF])

  }

  @Test func leavesALinkBetweenTwoDevicesAlone() throws {

    let records: [BackupRecord] = [
      Example.record(.responder, group: 1, Self.old, memory: 0x0FFF),
      Example.record(.responder, group: 5, Example.plug, memory: 0x0FF7),
      Example.end(0x0FEF)
    ]
    let plan = try Self.plan(Example.backup([Example.device(Example.lamp, records: records), Self.linked(Example.plug)]))
    let lamp = try #require(plan.devices.first { $0.address == Example.lamp })

    #expect(lamp.steps.compactMap(\.replaces?.address) == [Self.old])
    #expect(plan.steps.allSatisfy { $0.record?.address != Example.plug || $0.target == Self.new })

  }

  @Test func ignoresFreeAndEndRecordsThatNameTheOldModem() throws {

    let records: [BackupRecord] = [
      Example.record(.responder, group: 1, Self.old, state: .free, memory: 0x0FFF),
      Example.record(.responder, group: 1, Self.old, state: .end, memory: 0x0FF7)
    ]
    let plan = try Self.plan(Example.backup([Example.device(Example.lamp, records: records)], modemRecords: []))

    #expect(plan.steps.isEmpty)
    #expect(plan.unchangedDevices == [Example.lamp])

  }

  @Test func addsEachLinkToTheNewModemOnce() throws {

    let modem: [BackupRecord] = [Example.record(.controller, group: 1, Example.lamp), Example.record(.controller, group: 1, Example.lamp)]
    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)], modemRecords: modem))

    #expect(plan.modemSteps.count == 1)
    #expect(plan.modemFindings.map(\.kind) == [.duplicateModemRecord])

  }

  // MARK: - Every device, by engine

  @Test(arguments: [
    (BackupEngine.i1, ManualTransferReason.noRemoteWrites),
    (BackupEngine.i2cs, ManualTransferReason.rejectsUntilLinked)
  ]) func relinksAnI1OrI2CSDeviceByHand(engine: BackupEngine, reason: ManualTransferReason) throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp, engine: engine)]))

    #expect(plan.devices.isEmpty)
    #expect(plan.steps.isEmpty)
    #expect(plan.manual.map(\.reason) == [reason])
    #expect(plan.manual.first?.linksToRestore == [Example.record(.controller, group: 1, Example.lamp)])

  }

  @Test func relinksADeviceWhoseEngineTheBackupDoesNotSayByHand() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp, engine: nil)]))

    #expect(plan.manual.map(\.reason) == [.engineUnknown])

  }

  @Test func rewritesAnI2DeviceFromAfar() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp, engine: .i2)]))

    #expect(plan.devices.map(\.address) == [Example.lamp])
    #expect(plan.manual.isEmpty)

  }

  @Test(arguments: [BackupEngine.i1, .i2cs])
  func needsNothingFromADeviceWithNoLinkToTheOldModemWhatEverItsEngine(engine: BackupEngine) throws {

    let device: BackupDevice = Example.device(Example.lamp, engine: engine, records: [Example.record(.responder, group: 1, Example.plug, memory: 0x0FFF), Example.end(0x0FF7)])
    let plan = try Self.plan(Example.backup([device], modemRecords: []))

    #expect(plan.unchangedDevices == [Example.lamp])
    #expect(plan.manual.isEmpty)

  }

  // MARK: - Devices that can't be read

  @Test func relinksADeviceWithNoDatabaseByHandAndListsTheLinksTheOldModemHeld() throws {

    let modem: [BackupRecord] = [Example.record(.controller, group: 1, Example.sensor), Example.record(.responder, group: 2, Example.sensor)]
    let plan = try Self.plan(Example.backup([Example.unreadable(Example.sensor)], modemRecords: modem))
    let manual = try #require(plan.manual.first)

    #expect(manual.reason == .noDatabase)
    #expect(manual.linksToRestore == modem)
    #expect(plan.steps.isEmpty)

  }

  @Test func relinksADeviceWhoseDatabaseIsPartialByHand() throws {

    let partial: BackupDevice = Example.device(Example.lamp, records: [Example.record(.responder, group: 1, Self.old, memory: 0x0FFF)])
    let plan = try Self.plan(Example.backup([partial]))

    #expect(plan.manual.map(\.reason) == [.incompleteDatabase])
    #expect(plan.devices.isEmpty)

  }

  @Test func relinksADeviceWhoseRecordsHaveNoMemoryAddressByHand() throws {

    let records: [BackupRecord] = [Example.record(.responder, group: 1, Self.old), Example.end(0x0FF7)]
    let plan = try Self.plan(Example.backup([Example.device(Example.lamp, records: records)]))

    #expect(plan.manual.map(\.reason) == [.incompleteDatabase])

  }

  @Test func listsManualDevicesInAddressOrderWithTheStepsToTake() throws {

    let plan = try Self.plan(Example.backup([Example.unreadable(Example.plug), Example.unreadable(Example.sensor), Example.unreadable(Example.lamp)]))

    #expect(plan.manual.map(\.address) == [Example.sensor, Example.lamp, Example.plug])
    #expect(plan.manual.map(\.order) == [1, 2, 3])
    #expect(plan.manual.first?.steps.count == 3)
    #expect(plan.manual.first?.steps.first?.contains("SET button") == true)
    #expect(plan.manual.first?.steps[1].contains("\(Example.sensor)") == true)

  }

  @Test func relinksEveryDeviceByHandWhenTheBackupHoldsNoModemDatabase() throws {

    let backup: HomeBackup = HomeBackup(createdAt: Example.createdAt, source: .hubPro, modem: BackupModem(address: Self.old, unreadable: BackupUnreadable(reason: .unavailableFromSource)), devices: [Self.linked(Example.lamp), Example.unreadable(Example.plug)])
    let plan = try Self.plan(backup)

    #expect(plan.manual.map(\.reason) == [.noModemDatabase, .noModemDatabase])
    #expect(plan.steps.isEmpty)
    #expect(plan.warnings.contains { $0.contains("Hub Pro's device list") })

  }

  @Test func relinksEveryDeviceByHandWhenTheBackupNamesNoModem() throws {

    let backup: HomeBackup = HomeBackup(createdAt: Example.createdAt, source: .modem, modem: nil, devices: [Self.linked(Example.lamp)])
    let plan = try Self.plan(backup)

    #expect(plan.oldModem == nil)
    #expect(plan.manual.map(\.reason) == [.noModemDatabase])

  }

  // MARK: - Links that are already dead, duplicates and orphans

  @Test func leavesARecordAloneWhenTheOldModemHoldsNoMatchingOne() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)], modemRecords: []))
    let device = try #require(plan.devices.first)

    #expect(device.steps.isEmpty)
    #expect(device.findings.map(\.kind) == [.noMatchingModemRecord])
    #expect(plan.modemSteps.isEmpty)

  }

  @Test func doesNotCopyAModemRecordTheDeviceHasNoMatchFor() throws {

    let plan = try Self.plan(Example.backup([Example.device(Example.lamp, records: [Example.end(0x0FFF)])], modemRecords: [Example.record(.controller, group: 4, Example.lamp)]))

    #expect(plan.modemSteps.isEmpty)
    #expect(plan.modemFindings.map(\.kind) == [.noMatchingDeviceRecord])

  }

  @Test func rewritesTheFirstOfTwoIdenticalRecordsAndSaysAboutTheSecond() throws {

    let records: [BackupRecord] = [Example.record(.responder, group: 1, Self.old, memory: 0x0FFF), Example.record(.responder, group: 1, Self.old, memory: 0x0FF7), Example.end(0x0FEF)]
    let plan = try Self.plan(Example.backup([Example.device(Example.lamp, records: records)]))
    let device = try #require(plan.devices.first)

    #expect(device.steps.filter { $0.action == .rewriteRecord }.count == 1)
    #expect(device.findings.map(\.kind) == [.duplicateRecord])
    #expect(device.findings.first?.record.memoryAddress == 0x0FF7)

  }

  @Test func doesNotCopyARecordForAnAddressThatIsNotADeviceInTheBackup() throws {

    let stranger: InsteonAddress = InsteonAddress(0xAB, 0xCD, 0xEF)
    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)], modemRecords: [Example.record(.controller, group: 1, Example.lamp), Example.record(.controller, group: 1, stranger)]))

    #expect(plan.modemSteps.map(\.record?.address) == [Example.lamp])
    #expect(plan.modemFindings.map(\.kind) == [.recordForUnknownDevice])
    #expect(plan.modemFindings.first?.record.address == stranger)

  }

  @Test func neverTargetsAnAddressThatIsNeitherTheNewModemNorADeviceInTheBackup() throws {

    let stranger: InsteonAddress = InsteonAddress(0xAB, 0xCD, 0xEF)
    let backup: HomeBackup = Example.backup([Self.linked(Example.lamp), Self.linked(Example.plug, engine: .i1), Example.unreadable(Example.sensor)], modemRecords: [Example.record(.controller, group: 1, stranger), Example.record(.controller, group: 1, Example.lamp)])
    let plan = try Self.plan(backup)
    let allowed: Set<InsteonAddress> = Set(backup.devices.map(\.address)).union([Self.new])

    #expect(!plan.steps.isEmpty)
    #expect(plan.steps.allSatisfy { allowed.contains($0.target) })

  }

  // MARK: - Steps and their effects

  @Test func readsADeviceBeforeAndAfterItsRewrites() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]))
    let steps = try #require(plan.devices.first?.steps)

    #expect(steps.map(\.action) == [.readDatabase, .rewriteRecord, .readBack])
    #expect(steps.map(\.effect) == [.readOnly, .link, .readOnly])
    #expect(steps.first?.summary.contains("0x07") == true)

  }

  @Test func numbersTheStepsFromOneWithTheNewModemsFirst() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp), Self.linked(Example.plug)]))

    #expect(plan.steps.map(\.number) == Array(1...plan.steps.count))
    #expect(plan.steps.prefix(plan.modemSteps.count).allSatisfy { $0.target == Self.new })
    #expect(plan.devices.map(\.address) == [Example.lamp, Example.plug])

  }

  @Test func countsStepsByEffect() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]))

    #expect(plan.stepCounts == [.readOnly: 2, .link: 2])

  }

  // MARK: - Links the new modem already holds

  @Test func refusesWhenTheNewModemHoldsLinks() throws {

    let held: [BackupRecord] = [Example.record(.controller, group: 1, Example.outlet), Example.record(.controller, group: 2, Example.outlet)]

    #expect(throws: TransferPlanError.existingLinks(count: 2)) { try Self.plan(Example.backup([Self.linked(Example.lamp)]), held) }

  }

  @Test func countsOnlyRecordsInUseAsLinks() throws {

    let held: [BackupRecord] = [Example.record(.controller, group: 1, Example.outlet, state: .free), Example.record(.controller, group: 2, Example.outlet, state: .end)]
    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]), held)

    #expect(plan.existingLinks == .none)
    #expect(plan.existingLinkCount == 0)

  }

  @Test func mergesKeepingTheNewModemsLinksAndWarning() throws {

    let held: [BackupRecord] = [Example.record(.controller, group: 1, Example.outlet)]
    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]), held, .merge)

    #expect(plan.existingLinks == .merge)
    #expect(plan.existingLinkCount == 1)
    #expect(plan.warnings.count == 1)
    #expect(plan.warnings.first?.contains("Merging keeps them") == true)
    #expect(plan.modemSteps.filter { $0.effect == .destructive }.isEmpty)
    #expect(plan.modemSteps.map(\.action) == [.addModemRecord])

  }

  @Test func skipsALinkTheNewModemAlreadyHoldsAndSaysSo() throws {

    let held: [BackupRecord] = [Example.record(.controller, group: 1, Example.lamp)]
    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]), held, .merge)

    #expect(plan.modemSteps.isEmpty)
    #expect(plan.modemFindings.map(\.kind) == [.alreadyInPlace])
    #expect(plan.devices.first?.steps.contains { $0.action == .rewriteRecord } == true)

  }

  @Test func keepsTheNewModemsRecordWhenItsDataDiffers() throws {

    let held: [BackupRecord] = [Example.record(.controller, group: 1, Example.lamp, data: [0x09, 0x09, 0x09])]
    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]), held, .merge)

    #expect(plan.modemSteps.isEmpty)
    #expect(plan.modemFindings.map(\.kind) == [.conflictingModemRecord])
    #expect(plan.modemFindings.first?.summary.contains("09 09 09") == true)

  }

  @Test func replacesTheNewModemsDatabaseWithDestructiveStepsAndItsOwnWarning() throws {

    let held: [BackupRecord] = [Example.record(.controller, group: 2, Example.outlet), Example.record(.controller, group: 1, Example.outlet)]
    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]), held, .replaceDatabase)

    #expect(plan.existingLinks == .replaceDatabase)
    #expect(plan.warnings.first?.contains("destructive") == true)
    #expect(plan.modemSteps.map(\.action) == [.removeModemRecord, .removeModemRecord, .addModemRecord])
    #expect(plan.modemSteps.map(\.effect) == [.destructive, .destructive, .link])
    #expect(plan.modemSteps.compactMap(\.record?.group).prefix(2) == [1, 2])
    #expect(plan.stepCounts[.destructive] == 2)

  }

  @Test func choosingMergeOnAnEmptyNewModemChangesNothing() throws {

    let empty = try Self.plan(Example.backup([Self.linked(Example.lamp)]), [], .merge)
    let plain = try Self.plan(Example.backup([Self.linked(Example.lamp)]), [], .refuse)

    #expect(try empty.json() == (try plain.json()))
    #expect(empty.warnings.isEmpty)

  }

  @Test func assumesAnEmptyNewModemAndSaysWhenItsDatabaseWasNotRead() throws {

    let plan = try Self.plan(Example.backup([Self.linked(Example.lamp)]), nil)

    #expect(plan.existingLinks == .unread)
    #expect(plan.existingLinkCount == nil)
    #expect(plan.warnings.first?.contains("wasn't read") == true)
    #expect(!plan.modemSteps.isEmpty)

  }

  // MARK: - Refusing a plan

  @Test func refusesTheModemTheBackupWasTakenFrom() {

    #expect(throws: TransferPlanError.sameModem) {

      _ = try TransferPlanner.plan(from: Example.backup([Self.linked(Example.lamp)]), to: TransferTarget(address: Self.old, records: []))

    }

  }

  @Test func refusesANewModemThatIsADeviceInTheBackup() {

    #expect(throws: TransferPlanError.targetIsInBackup) {

      _ = try TransferPlanner.plan(from: Example.backup([Self.linked(Example.lamp)]), to: TransferTarget(address: Example.lamp, records: []))

    }

  }

  // MARK: - Determinism

  @Test func makesTheSamePlanBytesForTheSameInputs() throws {

    let backup: HomeBackup = Example.backup([Self.linked(Example.lamp), Self.linked(Example.plug, engine: .i1), Example.unreadable(Example.sensor)])

    #expect(try Self.plan(backup).json() == (try Self.plan(backup).json()))

  }

  @Test func makesTheSamePlanWhateverOrderTheBackupListsDevicesAndRecords() throws {

    let lampRecords: [BackupRecord] = [Example.record(.responder, group: 2, Self.old, memory: 0x0FEF), Example.record(.responder, group: 1, Self.old, memory: 0x0FFF), Example.end(0x0FE7)]
    let modem: [BackupRecord] = [Example.record(.controller, group: 1, Example.lamp), Example.record(.controller, group: 2, Example.lamp), Example.record(.controller, group: 1, Example.plug)]
    let one: HomeBackup = Example.backup([Example.device(Example.lamp, records: lampRecords), Self.linked(Example.plug)], modemRecords: modem)
    let other: HomeBackup = Example.backup([Self.linked(Example.plug), Example.device(Example.lamp, records: lampRecords)], modemRecords: modem.reversed())

    var first: TransferPlan = try Self.plan(one)
    let second: TransferPlan = try Self.plan(other)

    // The backups differ in the order they list, so their checksums differ; nothing else may.
    #expect(first.backupChecksum != second.backupChecksum)

    first.backupChecksum = second.backupChecksum

    #expect(try first.json() == (try second.json()))

  }

  @Test func holdsNoTimeSoARunLaterMakesTheSameBytes() throws {

    let early: HomeBackup = HomeBackup(createdAt: Date(timeIntervalSince1970: 1), source: .modem, modem: BackupModem(address: Self.old, allLinkDatabase: []), devices: [])
    let late: HomeBackup = HomeBackup(createdAt: Date(timeIntervalSince1970: 2), source: .modem, modem: BackupModem(address: Self.old, allLinkDatabase: []), devices: [])
    let text: String = String(decoding: try Self.plan(early).json(), as: UTF8.self)

    #expect(!text.contains("1970"))
    #expect(try Self.plan(early).json().count > 0)
    #expect(try Self.plan(early).backupChecksum != Self.plan(late).backupChecksum)

  }

  @Test func holdsNoDashCharactersInItsText() throws {

    let backup: HomeBackup = Example.backup([Self.linked(Example.lamp), Self.linked(Example.plug, engine: .i1)])
    let text: String = String(decoding: try Self.plan(backup, [Example.record(.controller, group: 1, Example.outlet)], .replaceDatabase).json(), as: UTF8.self)

    #expect(!text.contains("\u{2014}"))
    #expect(!text.contains("\u{2013}"))

  }

  // MARK: - Reading the new modem

  @Test func readsTheNewModemsAddressAndRecordsWithReadsOnly() async throws {

    let (modem, writes) = await Self.readOnlyModem()

    await modem.setModemRecords([AllLinkRecord(flags: [.inUse, .usedBefore, .controller], group: 1, address: Example.outlet, data1: 0x01)])

    let network = DeviceNetwork(modem: modem, catalog: nil, clock: TestClock())
    let target = try await TransferTarget.read(from: network)

    #expect(target.address == Example.oldModem)
    #expect(target.records == [Example.record(.controller, group: 1, Example.outlet, data: [0x01, 0x00, 0x00])])
    #expect(writes.all == [])

  }

  @Test func readsAHubProsModemAddressAndAsksForReadsOnly() async throws {

    let http = HubProNetworkTests.unit()
    let network = HubProNetwork(transport: HubProTransport(host: HubProUnit.host, httpClient: http), catalog: ControlExample.catalog, clock: TestClock(), now: { Date(timeIntervalSince1970: 1_000) })
    let target = try #require(await TransferTarget.read(hubPro: network))

    #expect(target.address == InsteonAddress(0xAA, 0xBB, 0xCC))
    #expect(target.records == nil)
    #expect(await http.sent.allSatisfy { $0.hasPrefix("GET ") })

  }

  /// A modem that records anything sent to it that isn't a read of its own database.
  static func readOnlyModem() async -> (InMemoryModem, WriteWatch) {

    let modem = InMemoryModem()
    let writes = WriteWatch()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case .readModemDatabase:
        break
      case .send, .standardRequest, .extendedRequest:
        writes.add("\(operation)")
      }

    }

    return (modem, writes)

  }

}
