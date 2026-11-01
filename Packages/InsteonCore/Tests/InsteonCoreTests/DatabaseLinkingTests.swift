import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Made-up devices for linking by writing ALL-Link databases.
enum DatabaseLinkingExample {

  static let module = InsteonAddress(0x2C, 0x3D, 0x01)

  static let lamp = InsteonAddress(0x2C, 0x3D, 0x02)

  static let stranger = InsteonAddress(0x55, 0x66, 0x77)

  /// A module whose catalog gives its links to a Hub and its responder record's data bytes.
  static let moduleIdentity = ReportedIdentity(category: 0x02, subcategory: 0x6F, firmwareVersion: 0x41)

  /// A module whose catalog gives no links to a Hub.
  static let legless = ReportedIdentity(category: 0x02, subcategory: 0x70, firmwareVersion: 0x41)

  /// A module whose responder record has a byte the catalog gives no value for.
  static let speedy = ReportedIdentity(category: 0x02, subcategory: 0x71, firmwareVersion: 0x41)

  /// A module whose catalog says it runs i2.
  static let older = ReportedIdentity(category: 0x02, subcategory: 0x72, firmwareVersion: 0x41)

  /// A module whose catalog doesn't say what its responder record's data bytes hold.
  static let plain = ReportedIdentity(category: 0x02, subcategory: 0x73, firmwareVersion: 0x41)

  static let responderBytes: [LinkDataByte] = [
    LinkDataByte(position: 1, name: "onLevel", summary: "The level the link turns the load to.", table: "onOff"),
    LinkDataByte(position: 2, name: "rampRate", summary: "How fast the load ramps."),
    LinkDataByte(position: 3, name: "button", summary: "The device's own group.", isPerGroup: true)
  ]

  static let commands = CommandSet(
    id: "exampleDatabase",
    name: "Example database",
    summary: "A relay whose responder records hold an on-level, a ramp rate and a group.",
    groupTypes: [
      GroupType(name: "load", label: "Load", kind: .relay, linkData: GroupType.LinkData(responder: responderBytes)),
      GroupType(
        name: "speedyLoad",
        label: "Load",
        kind: .relay,
        linkData: GroupType.LinkData(responder: [LinkDataByte(position: 1, name: "speed", summary: "A speed.")])
      ),
      GroupType(name: "plainLoad", label: "Load", kind: .relay)
    ]
  )

  static let legs: [DeviceLifecycle.HubLinking.Leg] = [
    DeviceLifecycle.HubLinking.Leg(modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01),
    DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
  ]

  static func profile(
    _ model: ProductModel,
    _ identity: ReportedIdentity,
    type: SettingName = "load",
    legs: [DeviceLifecycle.HubLinking.Leg] = legs,
    engines: [DeviceEngine] = []
  ) -> DeviceProfile {

    DeviceProfile(
      model: model,
      name: "Example \(model)",
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      engines: engines,
      commandSets: [CommandSetEntry(commandSet: "exampleDatabase", category: identity.category, subcategory: identity.subcategory)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .both, type: type)],
      lifecycle: legs.isEmpty ? nil : DeviceLifecycle(fromHub: DeviceLifecycle.HubLinking(legs: legs))
    )

  }

  static let catalog = DeviceCatalog(
    profiles: [
      profile("9501", moduleIdentity),
      profile("9502", legless, legs: []),
      profile("9503", speedy, type: "speedyLoad"),
      profile("9504", older, engines: [DeviceEngine(engine: .i2, category: older.category, subcategory: older.subcategory)]),
      profile("9505", plain, type: "plainLoad")
    ],
    commandSets: [commands]
  )

  /// The in-memory modem, whose catalog profile says what its own records hold.
  static let modemProfile = DeviceProfile(
    model: "9599",
    name: "Example Modem",
    identities: [DeviceIdentity(category: 0x03, subcategory: 0x15)],
    modemLinkData: ModemLinkData(
      controller: [
        ModemLinkDataByte(position: 1, name: "data1", summary: "Always 0x01.", value: 0x01),
        ModemLinkDataByte(position: 2, name: "subcategory", summary: "The responder's subcategory.", identity: .subcategory),
        ModemLinkDataByte(position: 3, name: "firmware", summary: "The responder's firmware version.", identity: .firmware)
      ],
      responder: [ModemLinkDataByte(position: 1, name: "category", summary: "The controller's category.", identity: .category)]
    )
  )

  static let catalogWithModem = DeviceCatalog(profiles: catalog.profiles + [modemProfile], commandSets: [commands])

}

/// Linking and unlinking by writing ALL-Link databases, on an in-memory modem.
@Suite(.timeLimit(.minutes(1)))
struct DatabaseLinkingTests {

  let clock: TestClock = TestClock()

  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)

  let device: InsteonAddress = DatabaseLinkingExample.module

  // MARK: - Records

  func controller(_ group: AllLinkGroupNumber, naming address: InsteonAddress, data: [UInt8] = [0x00, 0x00, 0x00]) -> AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: group, address: address, data1: data[0], data2: data[1], data3: data[2])

  }

  func responder(_ group: AllLinkGroupNumber, naming address: InsteonAddress, data: [UInt8] = [0x00, 0x00, 0x00]) -> AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: group, address: address, data1: data[0], data2: data[1], data3: data[2])

  }

  /// A record that was used and deleted: in use clear, used before set.
  func deleted(_ record: AllLinkRecord) -> AllLinkRecord {

    var record: AllLinkRecord = record
    record.flags.remove(.inUse)

    return record

  }

  let end: AllLinkRecord = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  // MARK: - Setup

  func pressed(_ identity: ReportedIdentity) -> SetButtonPressed {

    SetButtonPressed(sender: device, role: .responder, category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)

  }

  /// A modem with the module answering as i2CS and reporting an identity.
  func modem(identity: ReportedIdentity = DatabaseLinkingExample.moduleIdentity, engine: InsteonEngine = .i2cs) async -> InMemoryModem {

    let modem = InMemoryModem()
    await modem.setEngine(engine, of: device)
    await modem.setIdentity(pressed(identity))

    return modem

  }

  func network(_ modem: InMemoryModem, catalog: DeviceCatalog = DatabaseLinkingExample.catalog) -> DeviceNetwork {

    DeviceNetwork(modem: modem, catalog: catalog, clock: clock)

  }

  /// The module, holding a controller record of the modem in group 1 and a free slot below it.
  func partlyLinked() async -> InMemoryModem {

    let modem: InMemoryModem = await modem()

    await modem.setDatabase([
      0x0FFF: controller(0x01, naming: modemAddress),
      0x0FF7: deleted(responder(0x09, naming: DatabaseLinkingExample.lamp))
    ], of: device)

    return modem

  }

  // MARK: - Linking

  @Test func plansTheMissingRecordsOfTheCatalogsLinks() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let plan: DatabaseLinkPlan = try await network(modem).linking.planDatabaseLink(device)

    #expect(plan.direction == .link)
    #expect(plan.modem == modemAddress)
    #expect(plan.engine == .i2cs)
    #expect(plan.steps.map { $0.kind } == [.addDeviceRecord, .addModemRecord, .addModemRecord])
    #expect(plan.steps.map { $0.written } == [
      responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01]),
      controller(0x00, naming: device),
      responder(0x01, naming: device)
    ])
    #expect(plan.steps.map { $0.record.memoryAddress } == [0x0FF7, nil, nil])
    #expect(plan.linksInPlace == [LinkRecord(isController: true, isInUse: true, group: 0x01, address: modemAddress, data: [0x00, 0x00, 0x00], memoryAddress: 0x0FFF)])
    #expect(plan.orphans.isEmpty)

  }

  @Test func planningWritesNothing() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let log: OperationLog = await OperationLog.logging(modem)

    _ = try await network(modem).linking.planDatabaseLink(device)

    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemRecords.isEmpty)
    #expect(log.writesAndExtendedMessages == 0)
    #expect(log.standardCommands == [0x0D, 0x10])

  }

  @Test func linksBothSidesAndLeavesTheOtherRecordsAlone() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.steps.map { $0.outcome } == [.written, .written, .written])
    #expect(result.mismatches.isEmpty)
    #expect(result.deviceCheck == .checked)
    #expect(result.isComplete)
    #expect(await modem.writes == [InMemoryModem.Write(device: device, address: 0x0FF7)])
    #expect(await modem.record(of: device, at: 0x0FFF) == controller(0x01, naming: modemAddress))
    #expect(await modem.record(of: device, at: 0x0FF7) == responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01]))
    #expect(await modem.record(of: device, at: 0x0FEF) == end)
    #expect(await modem.modemRecords == [controller(0x00, naming: device), responder(0x01, naming: device)])

  }

  @Test func movesTheEndDownBeforeWritingItsSlot() async throws {

    let modem: InMemoryModem = await modem()

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    #expect(plan.deviceSteps.map { $0.kind } == [.markEndOfDatabase, .addDeviceRecord])
    #expect(plan.deviceSteps.map { $0.record.memoryAddress } == [0x0FEF, 0x0FF7])

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.isComplete)
    #expect(await modem.writes == [InMemoryModem.Write(device: device, address: 0x0FEF), InMemoryModem.Write(device: device, address: 0x0FF7)])
    #expect(await modem.record(of: device, at: 0x0FF7) == responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01]))
    #expect(await modem.record(of: device, at: 0x0FEF) == end)

  }

  @Test func plansNothingForALinkInPlace() async throws {

    let modem: InMemoryModem = await modem()

    await modem.setDatabase([
      0x0FFF: controller(0x01, naming: modemAddress),
      0x0FF7: responder(0x00, naming: modemAddress, data: [0x80, 0x1F, 0x01])
    ], of: device)
    await modem.setModemRecords([controller(0x00, naming: device), responder(0x01, naming: device)])

    let plan: DatabaseLinkPlan = try await network(modem).linking.planDatabaseLink(device)

    #expect(plan.isEmpty)
    #expect(plan.linksInPlace == [
      LinkRecord(isController: false, isInUse: true, group: 0x00, address: modemAddress, data: [0x80, 0x1F, 0x01], memoryAddress: 0x0FF7),
      LinkRecord(isController: true, isInUse: true, group: 0x00, address: device, data: [0x00, 0x00, 0x00]),
      LinkRecord(isController: false, isInUse: true, group: 0x01, address: device, data: [0x00, 0x00, 0x00]),
      LinkRecord(isController: true, isInUse: true, group: 0x01, address: modemAddress, data: [0x00, 0x00, 0x00], memoryAddress: 0x0FFF)
    ])

  }

  @Test func writesARecordOnceMoreWhenItReadsBackDifferently() async throws {

    let modem: InMemoryModem = await partlyLinked()

    await modem.setForgetful(device, writes: 1)

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let result: DatabaseLinkResult = try await linking.apply(try await linking.planDatabaseLink(device))

    #expect(result.steps.map { $0.outcome } == [.writtenOnRetry, .written, .written])
    #expect(result.isComplete)
    #expect(await modem.writes == [InMemoryModem.Write(device: device, address: 0x0FF7), InMemoryModem.Write(device: device, address: 0x0FF7)])

  }

  @Test func stopsAfterASecondWriteDoesntTake() async throws {

    let modem: InMemoryModem = await partlyLinked()

    await modem.setForgetful(device)

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let result: DatabaseLinkResult = try await linking.apply(try await linking.planDatabaseLink(device))

    #expect(result.steps.map { $0.outcome } == [.notWritten, .notReached, .notReached])
    #expect(!result.isComplete)
    #expect(result.mismatches.isEmpty)
    #expect(await modem.writes == [InMemoryModem.Write(device: device, address: 0x0FF7), InMemoryModem.Write(device: device, address: 0x0FF7)])
    #expect(await modem.modemRecords.isEmpty)

  }

  @Test func reportsARecordChangedBehindTheSteps() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let device: InsteonAddress = self.device
    let changed: AllLinkRecord = controller(0x07, naming: DatabaseLinkingExample.lamp)
    let modemAddress: InsteonAddress = self.modemAddress

    // While the device's record is written, something else rewrites its first record.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case .extendedRequest = operation {

        await modem.setDatabase([
          0x0FFF: changed,
          0x0FF7: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0x09, address: modemAddress)
        ], of: device)

      }

    }

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.steps.map { $0.outcome } == [.written, .written, .written])
    #expect(result.mismatches == [
      DatabaseMismatch(
        isDevice: true,
        memoryAddress: 0x0FFF,
        expected: LinkRecord(isController: true, isInUse: true, group: 0x01, address: modemAddress, data: [0x00, 0x00, 0x00], memoryAddress: 0x0FFF),
        found: LinkRecord(isController: true, isInUse: true, group: 0x07, address: DatabaseLinkingExample.lamp, data: [0x00, 0x00, 0x00], memoryAddress: 0x0FFF)
      )
    ])
    #expect(!result.isComplete)

  }

  @Test func refusesWhenADatabaseChangedSinceThePlan() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    await modem.setModemRecords([controller(0x00, naming: device)])

    let error: DatabaseLinkRefusal? = await #expect(throws: DatabaseLinkRefusal.self) {

      try await linking.apply(plan)

    }

    #expect(error == .changedSincePlanned(device))
    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemRecords == [controller(0x00, naming: device)])

  }

  // MARK: - Refusals

  func refusal(_ modem: InMemoryModem) async -> DatabaseLinkRefusal? {

    let linking: DeviceLinkingCoordinator = network(modem).linking

    return await #expect(throws: DatabaseLinkRefusal.self) {

      try await linking.planDatabaseLink(device)

    }

  }

  @Test func refusesADamagedDatabase() async {

    let modem: InMemoryModem = await partlyLinked()

    await modem.setDamaged(true, record: 0x0FFF, of: device)

    #expect(await refusal(modem) == .damagedRecords(device, count: 1))
    #expect(await modem.writes.isEmpty)

  }

  @Test func refusesADatabaseWithoutItsEnd() async {

    let modem: InMemoryModem = await modem()
    var records: [UInt16: AllLinkRecord] = [:]
    var address: UInt16 = 0x0FFF

    // Every slot the in-memory device reads holds a record in use, so none marks the end.
    while true {

      records[address] = address == 0x0FFF ? controller(0x01, naming: modemAddress) : responder(0x09, naming: DatabaseLinkingExample.lamp)

      guard address > 0x0007 else {

        break

      }

      address -= 8

    }

    await modem.setDatabase(records, of: device)

    #expect(await refusal(modem) == .noEndOfDatabase(device))

  }

  @Test func refusesAFullDatabase() async {

    let modem: InMemoryModem = await modem()
    var records: [UInt16: AllLinkRecord] = [:]
    var address: UInt16 = 0x0FFF

    // In use down to 0x030F, so the end is the lowest record, at 0x0307.
    while address >= 0x030F {

      records[address] = address == 0x0FFF ? controller(0x01, naming: modemAddress) : responder(0x09, naming: DatabaseLinkingExample.lamp)
      address -= 8

    }

    await modem.setDatabase(records, of: device)

    #expect(await refusal(modem) == .databaseFull(device, needed: 1, available: 0))

  }

  @Test func refusesADeviceTheCatalogDoesntDescribe() async {

    let modem: InMemoryModem = await modem(identity: ReportedIdentity(category: 0x02, subcategory: 0x7F, firmwareVersion: 0x41))

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    #expect(await refusal(modem) == .notInCatalog(device))

  }

  @Test func refusesADeviceThatReportsNoIdentity() async {

    // The device acknowledges ID Request but never sends its identity.
    let modem = InMemoryModem()

    await modem.setEngine(.i2cs, of: device)
    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let device: InsteonAddress = self.device
    let plan = Task { () async throws -> DatabaseLinkPlan in try await linking.planDatabaseLink(device) }

    await clock.waitForSleeper(until: Modem.defaultRequestTimeout)
    clock.advance(by: Modem.defaultRequestTimeout)

    let error: DatabaseLinkRefusal? = await #expect(throws: DatabaseLinkRefusal.self) {

      try await plan.value

    }

    #expect(error == .notIdentified(device))

  }

  @Test func refusesADeviceWithoutTheCatalogsLinks() async {

    let modem: InMemoryModem = await modem(identity: DatabaseLinkingExample.legless)

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    #expect(await refusal(modem) == .noCatalogLinks(device))

  }

  @Test func refusesAByteTheCatalogGivesNoValueFor() async {

    let modem: InMemoryModem = await modem(identity: DatabaseLinkingExample.speedy)

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    #expect(await refusal(modem) == .unknownLinkDataByte(device, name: "speed"))

  }

  @Test func refusesAnI2CSDeviceThatRejectsTheModem() async {

    let modem: InMemoryModem = await modem()

    await modem.setUnlinked(device)

    #expect(await refusal(modem) == .rejectsModem(device))
    #expect(await modem.writes.isEmpty)

  }

  @Test func refusesAnI2DeviceTheCatalogDoesntSayRunsI2() async {

    let modem: InMemoryModem = await modem(engine: .i2)

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    #expect(await refusal(modem) == .unsupportedEngine(device, .i2))

  }

  @Test func linksAnI2DeviceTheCatalogSaysRunsI2() async throws {

    let modem: InMemoryModem = await modem(identity: DatabaseLinkingExample.older, engine: .i2)

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    let plan: DatabaseLinkPlan = try await network(modem).linking.planDatabaseLink(device)

    #expect(plan.engine == .i2)
    #expect(plan.deviceSteps.map { $0.kind } == [.markEndOfDatabase, .addDeviceRecord])

  }

  @Test func refusesAnI1Device() async {

    let modem: InMemoryModem = await modem(engine: .i1)

    #expect(await refusal(modem) == .unsupportedEngine(device, .i1))

  }

  // MARK: - Unlinking

  /// The module linked both ways, with a record of a device the modem doesn't know, and the
  /// modem with a record of another device.
  func linked() async -> InMemoryModem {

    let modem: InMemoryModem = await modem()

    await modem.setDatabase([
      0x0FFF: controller(0x01, naming: modemAddress),
      0x0FF7: responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01]),
      0x0FEF: responder(0x05, naming: DatabaseLinkingExample.stranger)
    ], of: device)
    await modem.setModemRecords([
      controller(0x01, naming: device),
      responder(0x01, naming: device),
      controller(0x00, naming: DatabaseLinkingExample.lamp)
    ])

    return modem

  }

  @Test func unlinksBothSidesAndListsTheOrphans() async throws {

    let modem: InMemoryModem = await linked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseUnlink(device)

    #expect(plan.direction == .unlink)
    #expect(plan.steps.map { $0.kind } == [.removeModemRecord, .removeModemRecord, .removeDeviceRecord, .removeDeviceRecord])
    #expect(plan.deviceSteps.map { $0.record.memoryAddress } == [0x0FFF, 0x0FF7])
    #expect(plan.orphans == [LinkRecord(isController: false, isInUse: true, group: 0x05, address: DatabaseLinkingExample.stranger, data: [0x00, 0x00, 0x00], memoryAddress: 0x0FEF)])

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.steps.map { $0.outcome } == [.written, .written, .written, .written])
    #expect(result.isComplete)
    #expect(await modem.modemRecords == [controller(0x00, naming: DatabaseLinkingExample.lamp)])
    #expect(await modem.writes == [InMemoryModem.Write(device: device, address: 0x0FFF), InMemoryModem.Write(device: device, address: 0x0FF7)])
    #expect(await modem.record(of: device, at: 0x0FFF) == deleted(controller(0x01, naming: modemAddress)))
    #expect(await modem.record(of: device, at: 0x0FF7) == deleted(responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])))
    #expect(await modem.record(of: device, at: 0x0FEF) == responder(0x05, naming: DatabaseLinkingExample.stranger))

  }

  @Test func removesTheOrphansFirstWhenAsked() async throws {

    let modem: InMemoryModem = await linked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseUnlink(device, removingOrphans: true)

    #expect(plan.steps.map { $0.kind } == [.removeOrphanRecord, .removeModemRecord, .removeModemRecord, .removeDeviceRecord, .removeDeviceRecord])

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.isComplete)
    #expect(await modem.writes.map { $0.address } == [0x0FEF, 0x0FFF, 0x0FF7])
    #expect(await modem.record(of: device, at: 0x0FEF) == deleted(responder(0x05, naming: DatabaseLinkingExample.stranger)))

  }

  @Test func acceptsAnI2CSDeviceThatRejectsTheModemOnceUnlinked() async throws {

    let modem: InMemoryModem = await linked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseUnlink(device)

    // The device acknowledges removing its last record of the modem, then rejects the modem.
    await modem.setUnlinked(device, afterWrites: 2)

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.steps.map { $0.outcome } == [.written, .written, .written, .unverifiable])
    #expect(result.deviceCheck == .rejectsModemAfterUnlinking)
    #expect(result.mismatches.isEmpty)
    #expect(result.isComplete)
    #expect(await modem.record(of: device, at: 0x0FFF) == deleted(controller(0x01, naming: modemAddress)))
    #expect(await modem.record(of: device, at: 0x0FF7) == deleted(responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01])))

  }

  @Test func doesntCountAWriteTheDeviceRejectsAsDone() async throws {

    let modem: InMemoryModem = await linked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseUnlink(device)
    let device: InsteonAddress = self.device

    // The device rejects the modem before its last record of the modem is written.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case .extendedRequest = operation, await modem.writes.count == 1 {

        await modem.setUnlinked(device)

      }

    }

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.steps.map { $0.outcome } == [.written, .written, .written, .rejected])
    #expect(!result.isComplete)
    #expect(await modem.record(of: device, at: 0x0FF7) == responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01]))

  }

  @Test func unlinksBothModemRolesInAGroupWhicheverComesFirst() async throws {

    let modem: InMemoryModem = await modem()

    await modem.setDatabase([
      0x0FFF: controller(0x01, naming: modemAddress),
      0x0FF7: responder(0x01, naming: modemAddress)
    ], of: device)
    await modem.setModemRecords([responder(0x01, naming: device), controller(0x01, naming: device), controller(0x00, naming: DatabaseLinkingExample.lamp)])

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let result: DatabaseLinkResult = try await linking.apply(try await linking.planDatabaseUnlink(device))

    #expect(result.isComplete)
    #expect(await modem.modemRecords == [controller(0x00, naming: DatabaseLinkingExample.lamp)])

  }

  // MARK: - Partway

  @Test func countsAWriteThatTimesOutButReadsBackAsWritten() async throws {

    let modem: InMemoryModem = await partlyLinked()

    await modem.setUnacknowledged(device, writes: 1)

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let result: DatabaseLinkResult = try await linking.apply(try await linking.planDatabaseLink(device))

    #expect(result.steps.map { $0.outcome } == [.written, .written, .written])
    #expect(result.isComplete)
    #expect(await modem.writes == [InMemoryModem.Write(device: device, address: 0x0FF7)])

  }

  @Test func stopsAtAWriteThatsNeitherAnsweredNorReadBack() async throws {

    let modem: InMemoryModem = await partlyLinked()

    // The device doesn't acknowledge the write, then rejects the modem when it's read back.
    await modem.setUnacknowledged(device, writes: 1)
    await modem.setUnlinked(device, afterWrites: 1)

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let result: DatabaseLinkResult = try await linking.apply(try await linking.planDatabaseLink(device))

    #expect(result.steps.map { $0.outcome } == [.unanswered, .notReached, .notReached])
    #expect(result.deviceCheck == .unanswered)
    #expect(!result.isComplete)
    #expect(await modem.modemRecords.isEmpty)

  }

  @Test func keepsTheDatabaseWholeWhenTheRecordAfterANewEndIsntWritten() async throws {

    let modem: InMemoryModem = await modem()
    let device: InsteonAddress = self.device

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    // The new end is written, and the record in the old end's slot isn't.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case .extendedRequest = operation, await modem.writes.count == 1 {

        await modem.setForgetful(device)

      }

    }

    let result: DatabaseLinkResult = try await linking.apply(plan)

    #expect(result.steps.map { $0.outcome } == [.written, .notWritten, .notReached, .notReached])
    #expect(result.mismatches.isEmpty)
    #expect(await modem.record(of: device, at: 0x0FF7) == end)
    #expect(await modem.record(of: device, at: 0x0FEF) == end)
    #expect(await modem.modemRecords.isEmpty)

  }

  @Test func reportsAnAddTheModemRejects() async throws {

    let modem: InMemoryModem = await partlyLinked()

    // The modem's database is full.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .send(command) = operation, case .manageAllLinkRecord(.modifyFirstControllerOrAdd, _) = command {

        throw ModemError.rejected(.manageAllLinkRecord)

      }

    }

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let result: DatabaseLinkResult = try await linking.apply(try await linking.planDatabaseLink(device))

    #expect(result.steps.map { $0.outcome } == [.written, .rejected, .notReached])
    #expect(result.mismatches.isEmpty)
    #expect(!result.isComplete)

  }

  @Test func carriesTheStepsMadeWhenTheModemStopsAnswering() async throws {

    let modem: InMemoryModem = await partlyLinked()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case .send = operation {

        throw ModemError.timedOut(.manageAllLinkRecord)

      }

    }

    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let error: DatabaseLinkInterrupted? = await #expect(throws: DatabaseLinkInterrupted.self) {

      try await linking.apply(plan)

    }

    #expect(error?.result.steps.map { $0.outcome } == [.written, .unanswered, .notReached])
    #expect(error?.result.deviceCheck == .checked)
    #expect(error?.result.mismatches == [])
    #expect(error?.cause as? ModemError == .timedOut(.manageAllLinkRecord))

  }

  @Test func carriesTheStepsMadeWhenCanceled() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    // The task is canceled as the modem is sent its first record.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case .send = operation {

        withUnsafeCurrentTask { (task: UnsafeCurrentTask?) -> Void in task?.cancel() }

      }

    }

    let applying = Task { () async throws -> DatabaseLinkResult in try await linking.apply(plan) }
    let outcome: Result<DatabaseLinkResult, any Error> = await applying.result
    let error: DatabaseLinkInterrupted? = #expect(throws: DatabaseLinkInterrupted.self) { try outcome.get() }

    #expect(error?.cause is CancellationError)
    #expect(error?.result.steps.map { $0.outcome } == [.written, .unanswered, .notReached])
    #expect(error?.result.deviceCheck == .unanswered)
    #expect(await modem.modemRecords.isEmpty)

  }

  @Test func stopsBeforeWritingASlotThatChangedAfterTheCheck() async throws {

    let modem: InMemoryModem = await linked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseUnlink(device)
    let device: InsteonAddress = self.device
    let changed: AllLinkRecord = controller(0x07, naming: DatabaseLinkingExample.lamp)
    let others: [UInt16: AllLinkRecord] = [
      0x0FFF: changed,
      0x0FF7: responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01]),
      0x0FEF: responder(0x05, naming: DatabaseLinkingExample.stranger)
    ]

    // Something else writes the device's first slot while the modem's records are deleted.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case .send = operation {

        await modem.setDatabase(others, of: device)

      }

    }

    let error: DatabaseLinkInterrupted? = await #expect(throws: DatabaseLinkInterrupted.self) {

      try await linking.apply(plan)

    }

    #expect(error?.cause as? DatabaseLinkRefusal == .changedSincePlanned(device))
    #expect(error?.result.steps.map { $0.outcome } == [.written, .written, .notReached, .notReached])
    #expect(await modem.writes.isEmpty)
    #expect(await modem.record(of: device, at: 0x0FFF) == changed)

  }

  // MARK: - More refusals

  @Test func refusesALastRecordMarkedInUse() async {

    let modem: InMemoryModem = await modem()

    // The record that ends the database has never been used, yet it's marked in use.
    await modem.setDatabase([
      0x0FFF: controller(0x01, naming: modemAddress),
      0x0FF7: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x80), group: 0x00, address: DatabaseLinkingExample.lamp)
    ], of: device)

    #expect(await refusal(modem) == .noEndOfDatabase(device))

  }

  @Test func refusesAGroupWhoseLinkDataTheCatalogDoesntGive() async {

    let modem: InMemoryModem = await modem(identity: DatabaseLinkingExample.plain)

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    #expect(await refusal(modem) == .undescribedLinkData(device, group: 0x01))

  }

  @Test func refusesAnEngineThisPackageDoesntKnow() async {

    let modem: InMemoryModem = await modem()

    await modem.setUnknownEngine(0x05, of: device)

    #expect(await refusal(modem) == .unsupportedEngine(device, nil))

  }

  @Test func refusesWhenTheDevicesDatabaseChangedSinceThePlan() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    await modem.setDatabase([0x0FFF: controller(0x01, naming: modemAddress)], of: device)

    let error: DatabaseLinkRefusal? = await #expect(throws: DatabaseLinkRefusal.self) {

      try await linking.apply(plan)

    }

    #expect(error == .changedSincePlanned(device))
    #expect(await modem.writes.isEmpty)

  }

  @Test func refusesAPlanForAnotherModem() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    var plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    plan.modem = InsteonAddress(0x44, 0x55, 0x66)

    let other: DatabaseLinkPlan = plan
    let error: DatabaseLinkRefusal? = await #expect(throws: DatabaseLinkRefusal.self) {

      try await linking.apply(other)

    }

    #expect(error == .changedSincePlanned(device))
    #expect(await modem.writes.isEmpty)

  }

  // MARK: - The modem's record data

  @Test func writesTheModemsRecordsAsTheCatalogSaysTheModemDoes() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let plan: DatabaseLinkPlan = try await network(modem, catalog: DatabaseLinkingExample.catalogWithModem).linking.planDatabaseLink(device)

    #expect(plan.modemSteps.map { $0.written } == [
      controller(0x00, naming: device, data: [0x01, 0x6F, 0x41]),
      responder(0x01, naming: device, data: [0x02, 0x00, 0x00])
    ])

  }

}

