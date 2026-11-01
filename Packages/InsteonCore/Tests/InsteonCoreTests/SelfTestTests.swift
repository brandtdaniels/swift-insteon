import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Every operation a modem began, in order, from any task.
final class OperationLog: @unchecked Sendable {

  private let lock: NSLock = NSLock()

  private var operations: [InMemoryModem.Operation] = []

  /// The operations so far.
  var all: [InMemoryModem.Operation] {

    lock.withLock { operations }

  }

  /// The cmd1 of each standard message sent, in order.
  var standardCommands: [UInt8] {

    all.compactMap { (operation: InMemoryModem.Operation) -> UInt8? in

      guard case let .standardRequest(message) = operation else {

        return nil

      }

      return message.command.command1

    }

  }

  /// How many serial commands and extended messages were sent: none, for a test that only
  /// reads with standard messages.
  var writesAndExtendedMessages: Int {

    all.filter { (operation: InMemoryModem.Operation) -> Bool in

      switch operation {
      case .send, .extendedRequest:
        true
      case .standardRequest, .readModemDatabase:
        false
      }

    }.count

  }

  /// Adds an operation.
  func append(_ operation: InMemoryModem.Operation) {

    lock.withLock { operations.append(operation) }

  }

  /// Logs every operation of a modem.
  static func logging(_ modem: InMemoryModem) async -> OperationLog {

    let log = OperationLog()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      log.append(operation)

    }

    return log

  }

}

/// ``Device/selfTest(_:)`` on an in-memory modem.
@Suite(.timeLimit(.minutes(1)))
struct SelfTestTests {

  let clock: TestClock = TestClock()

  /// The in-memory modem's own address.
  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)

  /// The kinds of the checks a test without Beep runs, in order.
  let kinds: [SelfTestCheckKind] = [.answers, .catalog, .status, .linkDatabase, .modemLinks, .leftoverRecords, .operatingFlags]

  func pressed(_ device: InsteonAddress, _ identity: ReportedIdentity) -> SetButtonPressed {

    SetButtonPressed(sender: device, role: .responder, category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)

  }

  /// The modem's controller record for a device in a group.
  func controls(_ device: InsteonAddress, group: AllLinkGroupNumber = 0x00) -> AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: group, address: device)

  }

  /// A responder record naming a controller in a group.
  func responds(to controller: InsteonAddress, group: AllLinkGroupNumber = 0x00) -> AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: group, address: controller)

  }

  func network(_ modem: InMemoryModem, catalog: DeviceCatalog = Example.catalog) -> DeviceNetwork {

    DeviceNetwork(modem: modem, catalog: catalog, clock: clock)

  }

  /// A modem with a device answering as an engine and identity, linked with the modem as
  /// controller in group 0.
  func linked(_ device: InsteonAddress = Example.plug, identity: ReportedIdentity = Example.plugIdentity, engine: InsteonEngine = .i2cs) async -> InMemoryModem {

    let modem = InMemoryModem()
    await modem.setEngine(engine, of: device)
    await modem.setIdentity(pressed(device, identity))
    await modem.setModemRecords([controls(device)])
    await modem.setDatabase([0x0FFF: responds(to: modemAddress)], of: device)

    return modem

  }

  // MARK: - A healthy device

  @Test func passesAHealthyDeviceAndOnlyReads() async throws {

    let modem: InMemoryModem = await linked()
    let log: OperationLog = await OperationLog.logging(modem)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let product: String = try #require(report.productName)

    #expect(report.checks.map(\.kind) == kinds)
    #expect(report.checks.map(\.outcome) == [.passed, .passed, .passed, .passed, .passed, .passed, .skipped])
    #expect(report.check(.answers)?.detail == "The device answered and accepts the modem.")
    #expect(report.check(.catalog)?.detail == "The Insteon device catalog describes the device as \(product).")
    #expect(report.check(.status)?.detail == "The device reported its state.")
    #expect(report.check(.linkDatabase)?.detail == "1 record in use, each with its checksum intact.")
    #expect(report.check(.modemLinks)?.detail == "The device and the modem hold both records of the link.")
    #expect(report.check(.leftoverRecords)?.detail == "Every record names the modem or a device the modem is linked to.")
    #expect(report.check(.operatingFlags)?.detail == "The Insteon device catalog describes no operating flags for the device.")
    #expect(report.checks.allSatisfy(\.fixes.isEmpty))
    #expect(report.outcome == .passed)
    #expect(report.engine == .i2cs)
    #expect(report.identity == Example.plugIdentity)
    #expect(report.checklist == [.powerCycle])

    // Get Insteon Engine Version, ID Request, the status request, and the status request that
    // asks for the database's delta; then the database and the modem's are read. Nothing is
    // written, and no linking is started.
    #expect(log.standardCommands == [0x0D, 0x10, 0x19, 0x19])
    #expect(log.writesAndExtendedMessages == 0)
    #expect(await modem.linkingSteps == [.device(Example.plug, Command(command1: 0x0D), isExtended: false)])
    #expect(await modem.modemDeletions == 0)
    #expect(await modem.modemRecords == [controls(Example.plug)])
    #expect(await modem.databases[Example.plug] == [0x0FFF: responds(to: modemAddress)])

  }

  @Test func readsTheDatabaseFromTheDeviceNotACopy() async throws {

    let modem: InMemoryModem = await linked()
    let network: DeviceNetwork = self.network(modem)
    let gone = InsteonAddress(0x0E, 0x0E, 0x0E)

    // The network holds a copy, then the device's database changes without its delta.
    _ = try await network.allLinkDatabase(of: Example.plug)
    await modem.setDatabase([0x0FFF: responds(to: modemAddress), 0x0FF7: responds(to: gone, group: 0x02)], of: Example.plug)

    let report: SelfTestReport = try await network.device(Example.plug).selfTest()

    #expect(await modem.databaseReads[Example.plug] == 2)
    #expect(report.check(.leftoverRecords)?.fixes == [.reviewRecords([gone])])
    #expect(report.check(.leftoverRecords)?.detail == "Some records name devices the modem isn't linked to, which may be gone: 0E.0E.0E.")
    #expect(report.outcome == .warning)

  }

  // MARK: - Devices that don't answer

  @Test func failsADeviceThatDoesntAnswerAndSkipsTheRest() async throws {

    let modem = InMemoryModem()
    await modem.setUnanswering(Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let answers: SelfTestCheck = try #require(report.check(.answers))

    #expect(answers.outcome == .failed)
    #expect(answers.detail == "The device didn't answer Get Insteon Engine Version.")
    #expect(answers.fixes == [.checkSignal, .link(modemRole: nil, group: nil), .factoryReset])
    #expect(report.checks.map(\.kind) == kinds)
    #expect(report.checks.dropFirst().allSatisfy { (check: SelfTestCheck) -> Bool in check.outcome == .skipped })
    #expect(report.outcome == .failed)
    #expect(report.checklist == [.powerCycle])

  }

  @Test func saysWhenTheDeviceAnsweredItsEngineButNotIDRequest() async throws {

    let modem: InMemoryModem = await linked()
    let plug: InsteonAddress = Example.plug
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .standardRequest(message) = operation, message.command.command1 == 0x10 {

        throw ModemError.deviceTimedOut(plug)

      }

    }

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()

    #expect(report.check(.answers)?.outcome == .failed)
    #expect(report.check(.answers)?.detail == "The device didn't answer ID Request.")

  }

  @Test func failsAnUnlinkedI2CSDeviceTheSameWay() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(Example.plug)
    let log: OperationLog = await OperationLog.logging(modem)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest(SelfTestOptions(actuates: true))
    let answers: SelfTestCheck = try #require(report.check(.answers))

    #expect(answers.outcome == .failed)
    #expect(answers.detail == "The device answered, but rejects the modem: it runs i2CS and isn't linked to it.")
    #expect(answers.fixes == [.link(modemRole: nil, group: nil)])
    #expect(report.checks.map(\.kind) == kinds + [.beep])
    #expect(report.checks.dropFirst().allSatisfy { (check: SelfTestCheck) -> Bool in check.outcome == .skipped })
    #expect(report.checklist == [.powerCycle])
    #expect(!log.standardCommands.contains(0x30))

  }

  // MARK: - Identity and the catalog

  @Test func warnsOfADeviceTheCatalogDoesntDescribe() async throws {

    let modem: InMemoryModem = await linked(identity: ReportedIdentity(category: 0x02, subcategory: 0x55, firmwareVersion: 0x41))

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let catalog: SelfTestCheck = try #require(report.check(.catalog))

    #expect(catalog.outcome == .warning)
    #expect(catalog.detail == "The Insteon device catalog doesn't describe the identity the device reported, so the checks that need it are skipped.")
    #expect(catalog.fixes == [.updateCatalog])
    #expect(report.productName == nil)

  }

  @Test func testsADeviceThatReportsNoIdentityWithoutTheCatalogOrAskingAgain() async throws {

    // The device acknowledges ID Request but never sends its identity.
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: Example.plug)
    await modem.setModemRecords([controls(Example.plug)])
    await modem.setDatabase([0x0FFF: responds(to: modemAddress)], of: Example.plug)
    let log: OperationLog = await OperationLog.logging(modem)
    let network: DeviceNetwork = self.network(modem)

    let test = Task { () async throws -> SelfTestReport in try await network.device(Example.plug).selfTest(SelfTestOptions(actuates: true)) }

    await clock.waitForSleeper(until: Modem.defaultRequestTimeout)
    clock.advance(by: Modem.defaultRequestTimeout)

    let report: SelfTestReport = try await test.value

    #expect(report.identity == nil)
    #expect(report.check(.catalog)?.outcome == .warning)
    #expect(report.check(.catalog)?.fixes == [.readAgain, .checkSignal])
    #expect(report.check(.status)?.outcome == .skipped)
    #expect(report.check(.operatingFlags)?.outcome == .skipped)
    #expect(report.check(.beep)?.outcome == .skipped)
    // One ID Request, and no Beep.
    #expect(log.standardCommands.filter { (command1: UInt8) -> Bool in command1 == 0x10 }.count == 1)
    #expect(!log.standardCommands.contains(0x30))

  }

  // MARK: - The database

  @Test func failsADamagedRecordWithoutCallingItAMissingLink() async throws {

    let modem: InMemoryModem = await linked()
    await modem.setDamaged(true, record: 0x0FFF, of: Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()

    #expect(report.check(.linkDatabase)?.outcome == .failed)
    #expect(report.check(.linkDatabase)?.detail == "1 of the database's records failed their checksum, so what they hold can't be trusted.")
    #expect(report.check(.linkDatabase)?.fixes == [.readAgain, .checkSignal])

    for kind in [SelfTestCheckKind.modemLinks, .leftoverRecords] {

      #expect(report.check(kind)?.outcome == .warning)
      #expect(report.check(kind)?.fixes == [.readAgain])

    }

  }

  @Test func doesntCheckChecksumsOfAnOlderDevice() async throws {

    let modem: InMemoryModem = await linked(engine: .i2)
    // An i2 device sends no checksum, so its records arrive failing the check.
    await modem.setDamaged(true, record: 0x0FFF, of: Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()

    #expect(report.check(.linkDatabase)?.outcome == .passed)
    #expect(report.check(.linkDatabase)?.detail == "1 record in use. The device's engine sends no checksums to check.")
    #expect(report.check(.modemLinks)?.outcome == .passed)
    #expect(report.outcome == .passed)

  }

  // MARK: - Links

  @Test func failsALinkThatsMissingTheDevicesRecord() async throws {

    let modem: InMemoryModem = await linked()
    await modem.setDatabase([:], of: Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let links: SelfTestCheck = try #require(report.check(.modemLinks))

    #expect(links.outcome == .failed)
    #expect(links.detail == "A link is missing a record, so it works one way only, or not at all: the device's responder record for group 0.")
    #expect(links.fixes == [.link(modemRole: .controller, group: 0), .checkSignal])
    #expect(report.outcome == .failed)

  }

  @Test func checksEachLegTheCatalogGives() async throws {

    let module: InsteonAddress = HubLinkingExample.module
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: module)
    await modem.setIdentity(pressed(module, HubLinkingExample.moduleIdentity))
    // The modem controls the module in group 0, and responds to its group 1.
    await modem.setModemRecords([controls(module, group: 0x00), responds(to: module, group: 0x01)])
    await modem.setDatabase([
      0x0FFF: responds(to: modemAddress, group: 0x00),
      0x0FF7: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: modemAddress)
    ], of: module)

    let report: SelfTestReport = try await network(modem, catalog: HubLinkingExample.catalog).device(module).selfTest()

    #expect(report.check(.modemLinks)?.outcome == .passed)
    #expect(report.check(.modemLinks)?.detail == "The device and the modem hold both records of the 2 links the Insteon device catalog gives.")
    #expect(report.checklist == [.pressButton(group: 1), .powerCycle])

  }

  @Test func failsALegMissingTheModemsRecordInTheDevicesGroup() {

    let legs: [HubLinkingLeg] = [
      HubLinkingLeg(device: Example.plug, index: 0, count: 2, modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01),
      HubLinkingLeg(device: Example.plug, index: 1, count: 2, modemRole: .responder, modemGroup: 0x00, deviceGroup: 0x02)
    ]
    let deviceRecords: [LinkRecord] = [
      LinkRecord(isController: false, isInUse: true, group: 0x00, address: modemAddress, data: [0, 0, 0]),
      LinkRecord(isController: true, isInUse: true, group: 0x02, address: modemAddress, data: [0, 0, 0])
    ]
    let modemRecords: [LinkRecord] = [
      LinkRecord(isController: true, isInUse: true, group: 0x00, address: Example.plug, data: [0, 0, 0])
    ]

    let check: SelfTestCheck = Device.linksCheck(
      device: Example.plug,
      modem: modemAddress,
      deviceRecords: deviceRecords,
      modemRecords: modemRecords,
      legs: legs
    )

    // The modem's responder record holds the group the device controls.
    #expect(check.outcome == .failed)
    #expect(check.detail == "A link is missing a record, so it works one way only, or not at all: the modem's responder record for group 2.")
    // With the catalog's legs, linking again makes them all.
    #expect(check.fixes == [.link(modemRole: nil, group: nil), .checkSignal])

  }

  @Test func failsADeviceNeitherSideHasARecordOf() {

    let check: SelfTestCheck = Device.linksCheck(device: Example.plug, modem: modemAddress, deviceRecords: [], modemRecords: [], legs: nil)

    #expect(check.outcome == .failed)
    #expect(check.detail == "Neither the device nor the modem holds a record of a link with the other.")
    #expect(check.fixes == [.link(modemRole: nil, group: nil)])

  }

  // MARK: - Operating flags

  /// A command set with a programming lock and a key beep in one flags byte.
  static let lockedCommands = CommandSet(
    id: "exampleLock",
    name: "Example lock",
    summary: "A programming lock and a key beep.",
    operatingFlags: [
      OperatingFlag(name: "programmingLock", summary: "Locks programming.", query: .operatingFlags, bit: 0x01, label: "Programming lock"),
      OperatingFlag(name: "keyBeep", summary: "Beeps on every button press.", query: .operatingFlags, bit: 0x02, label: "Key beep")
    ]
  )

  static let lockedIdentity = ReportedIdentity(category: 0x02, subcategory: 0x61, firmwareVersion: 0x45)

  static let lockedCatalog = DeviceCatalog(
    profiles: [ControlExample.profile(model: "9160", name: "Example Lockable", identity: lockedIdentity, commands: lockedCommands, groups: [])],
    commandSets: [lockedCommands]
  )

  @Test func warnsOfAProgrammingLockTheDeviceReportsOn() async throws {

    let modem: InMemoryModem = await linked(identity: Self.lockedIdentity)
    await modem.setOperatingFlags(0x01, of: Example.plug)
    let log: OperationLog = await OperationLog.logging(modem)

    let report: SelfTestReport = try await network(modem, catalog: Self.lockedCatalog).device(Example.plug).selfTest()
    let flags: SelfTestCheck = try #require(report.check(.operatingFlags))

    #expect(flags.outcome == .warning)
    #expect(flags.detail == "Programming lock is on, so the device's buttons can't change its links or settings.")
    #expect(flags.fixes == [.turnOffProgrammingLock])
    // The flags are read with Get Operating Flags, and nothing sets them.
    #expect(log.standardCommands.contains(0x1F))
    #expect(!log.standardCommands.contains(0x20))
    #expect(log.writesAndExtendedMessages == 0)

  }

  func reading(_ commands: CommandSet = Self.lockedCommands, flags: UInt8?) -> DeviceSettingsReading {

    DeviceSettingsReading(
      productName: nil,
      commandSet: commands,
      items: commands.settingItems,
      operatingFlags: flags.map { (byte: UInt8) -> [OperatingFlagsRequest: UInt8] in [.operatingFlags: byte] } ?? [:],
      values: [:],
      buttons: [0x01]
    )

  }

  @Test func passesFlagsThatNeitherLockNorCutOff() {

    let check: SelfTestCheck = Device.flagsCheck(reading(flags: 0x02))

    #expect(check.outcome == .passed)
    #expect(check.detail == "2 operating flags read; none locks the device or cuts it off.")

  }

  @Test func warnsWhenNoFlagIsReported() {

    let check: SelfTestCheck = Device.flagsCheck(reading(flags: nil))

    #expect(check.outcome == .warning)
    #expect(check.detail == "The device reported none of its operating flags.")
    #expect(check.fixes == [.readAgain])

  }

  @Test func warnsOfRadioOffAndOfGuardedFlagsInAStateTheyreNeverWrittenTo() {

    let commands = CommandSet(
      id: "exampleGuarded",
      name: "Example guarded",
      summary: "Flags the catalog guards.",
      operatingFlags: [
        OperatingFlag(name: "radioOff", summary: "Turns the radio off.", query: .operatingFlags, bit: 0x01, label: "Radio off"),
        OperatingFlag(name: "lockButtons", summary: "Locks the buttons.", query: .operatingFlags, bit: 0x02, label: "Lock buttons", writeGuard: .neverSet),
        OperatingFlag(name: "messageForm", summary: "The message form.", query: .operatingFlags, bit: 0x04, label: "Message form", defaultValue: false, writeGuard: .keep),
        OperatingFlag(name: "keyBeep", summary: "Beeps on every button press.", query: .operatingFlags, bit: 0x08, label: "Key beep")
      ]
    )

    let check: SelfTestCheck = Device.flagsCheck(reading(commands, flags: 0x0F))

    #expect(check.outcome == .warning)
    #expect(check.detail == "Radio off is on, which cuts the device off from the modem; "
      + "Lock buttons is on, which the Insteon device catalog says is never turned on; "
      + "Message form is on, unlike the device as it leaves the factory, and isn't written.")
    #expect(check.fixes == [.factoryReset])

    #expect(Device.flagsCheck(reading(commands, flags: 0x08)).outcome == .passed)

  }

  // MARK: - Beep

  /// A relay whose command set lists Beep.
  static let beepingIdentity = ReportedIdentity(category: 0x02, subcategory: 0x60, firmwareVersion: 0x45)

  static let beepingCommands = CommandSet(
    id: "exampleBeepingRelay",
    name: "Example beeping relay",
    summary: "A relay with Beep.",
    standardCommands: [ControlExample.lightOn, ControlExample.lightOff, ControlExample.readOnOff, ControlExample.beep],
    groupTypes: [ControlExample.load]
  )

  static let beepingCatalog = DeviceCatalog(
    profiles: [
      ControlExample.profile(model: "9150", name: "Example Beeping Relay", identity: beepingIdentity, commands: beepingCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both, type: "load")
      ])
    ],
    commandSets: [beepingCommands]
  )

  @Test func beepsOnlyWhenAskedAndTheCatalogListsBeepAndLeavesTheLevel() async throws {

    let relay = InsteonAddress(0x3A, 0x4B, 0x60)
    let modem: InMemoryModem = await linked(relay, identity: Self.beepingIdentity)
    await modem.setLevel(0xFF, of: relay)
    let log: OperationLog = await OperationLog.logging(modem)
    let device: Device = network(modem, catalog: Self.beepingCatalog).device(relay)

    let reading: SelfTestReport = try await device.selfTest()

    #expect(reading.check(.beep) == nil)
    #expect(!log.standardCommands.contains(0x30))

    let actuated: SelfTestReport = try await device.selfTest(SelfTestOptions(actuates: true))

    #expect(actuated.checks.map(\.kind) == kinds + [.beep])
    #expect(actuated.check(.beep)?.outcome == .passed)
    #expect(actuated.check(.beep)?.detail == "The device acknowledged Beep.")
    #expect(log.standardCommands.filter { (command1: UInt8) -> Bool in command1 == 0x30 }.count == 1)
    // Beep leaves the load as it was, and nothing else is sent that changes it.
    #expect(await modem.levels[relay] == 0xFF)
    #expect(!log.standardCommands.contains { (command1: UInt8) -> Bool in [0x11, 0x13, 0x20].contains(command1) })
    #expect(log.writesAndExtendedMessages == 0)

  }

  @Test func sendsNoBeepToADeviceTheCatalogDoesntDescribe() async throws {

    let modem: InMemoryModem = await linked(identity: ReportedIdentity(category: 0x02, subcategory: 0x55, firmwareVersion: 0x41))
    let log: OperationLog = await OperationLog.logging(modem)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest(SelfTestOptions(actuates: true))

    #expect(report.check(.beep)?.outcome == .skipped)
    #expect(report.check(.beep)?.detail == "The Insteon device catalog doesn't list a Beep that's sent to the device, so nothing was sent.")
    #expect(!log.standardCommands.contains(0x30))

  }

  @Test func sendsNoBeepWhenTheCatalogDoesntListIt() async throws {

    let modem: InMemoryModem = await linked()
    let log: OperationLog = await OperationLog.logging(modem)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest(SelfTestOptions(actuates: true))

    #expect(report.check(.beep)?.outcome == .skipped)
    #expect(!log.standardCommands.contains(0x30))

  }

  // MARK: - Errors that aren't the device's

  @Test func rethrowsTheModemsErrors() async throws {

    let modem: InMemoryModem = await linked()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case .readModemDatabase = operation {

        throw ModemError.connectionClosed

      }

    }

    await #expect(throws: ModemError.connectionClosed) {

      try await network(modem).device(Example.plug).selfTest()

    }

  }

  @Test func rethrowsCancellation() async throws {

    let modem: InMemoryModem = await linked()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      throw CancellationError()

    }

    await #expect(throws: CancellationError.self) {

      try await network(modem).device(Example.plug).selfTest()

    }

  }

  // MARK: - The report

  @Test func sumsUpTheWorstOutcomeLeavingOutSkippedChecks() {

    let passed = SelfTestCheck(kind: .answers, outcome: .passed, detail: "")
    let skipped = SelfTestCheck(kind: .status, outcome: .skipped, detail: "")
    let warning = SelfTestCheck(kind: .leftoverRecords, outcome: .warning, detail: "")
    let failed = SelfTestCheck(kind: .modemLinks, outcome: .failed, detail: "")

    #expect(SelfTestReport(device: Example.plug, checks: [passed, skipped]).outcome == .passed)
    #expect(SelfTestReport(device: Example.plug, checks: [passed, warning, skipped]).outcome == .warning)
    #expect(SelfTestReport(device: Example.plug, checks: [failed, warning]).outcome == .failed)

  }

}
