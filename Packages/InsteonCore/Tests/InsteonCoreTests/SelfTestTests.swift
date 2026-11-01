import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// The standard messages a modem was sent, in order, from any task.
final class SentMessages: @unchecked Sendable {

  private let lock: NSLock = NSLock()

  private var messages: [StandardMessage] = []

  /// The messages so far.
  var all: [StandardMessage] {

    lock.withLock { messages }

  }

  /// Adds a message.
  func append(_ message: StandardMessage) {

    lock.withLock { messages.append(message) }

  }

}

/// ``Device/selfTest(_:)`` on an in-memory modem.
@Suite(.timeLimit(.minutes(1)))
struct SelfTestTests {

  let clock: TestClock = TestClock()

  /// The in-memory modem's own address.
  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)

  /// A plug the example catalog describes, linked with the modem as controller in group 0.
  var plugPressed: SetButtonPressed {

    SetButtonPressed(sender: Example.plug, role: .responder, category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

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

  /// A modem with the plug answering and linked with the modem as controller in group 0.
  func linkedPlug() async -> InMemoryModem {

    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: Example.plug)
    await modem.setIdentity(plugPressed)
    await modem.setModemRecords([controls(Example.plug)])
    await modem.setDatabase([0x0FFF: responds(to: modemAddress)], of: Example.plug)

    return modem

  }

  // MARK: - Whole tests

  @Test func passesAHealthyDeviceAndOnlyReads() async throws {

    let modem: InMemoryModem = await linkedPlug()
    let sent = SentMessages()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .standardRequest(message) = operation {

        sent.append(message)

      }

    }

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()

    #expect(report.checks.map(\.kind) == [.answers, .catalog, .status, .linkDatabase, .modemLinks, .leftoverRecords, .operatingFlags])
    #expect(report.check(.answers)?.outcome == .passed)
    #expect(report.check(.catalog)?.outcome == .passed)
    #expect(report.check(.linkDatabase)?.outcome == .passed)
    #expect(report.check(.modemLinks)?.outcome == .passed)
    #expect(report.check(.leftoverRecords)?.outcome == .passed)
    #expect(report.check(.operatingFlags)?.outcome == .skipped)
    #expect(report.outcome == .passed)
    #expect(report.engine == .i2cs)
    #expect(report.identity == Example.plugIdentity)
    #expect(report.productName != nil)
    #expect(report.checklist == [.powerCycle])

    // Only Get Insteon Engine Version, ID Request and status requests: nothing that changes
    // the device.
    let commands: Set<UInt8> = Set(sent.all.map { (message: StandardMessage) -> UInt8 in message.command.command1 })

    #expect(commands.isSubset(of: [0x0D, 0x10, 0x19]))
    #expect(await modem.modemDeletions == 0)

  }

  @Test func failsADeviceThatDoesntAnswerAndSkipsTheRest() async throws {

    let modem = InMemoryModem()
    await modem.setUnanswering(Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let answers: SelfTestCheck = try #require(report.check(.answers))

    #expect(answers.outcome == .failed)
    #expect(answers.fixes == [.checkSignal, .link, .factoryReset])
    #expect(report.checks.dropFirst().allSatisfy { (check: SelfTestCheck) -> Bool in check.outcome == .skipped })
    #expect(report.checks.count == 7)
    #expect(report.outcome == .failed)
    #expect(report.checklist == [.powerCycle])

  }

  @Test func failsAnUnlinkedI2CSDevice() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest(SelfTestOptions(actuates: true))
    let answers: SelfTestCheck = try #require(report.check(.answers))

    #expect(answers.outcome == .failed)
    #expect(answers.fixes == [.link])
    #expect(report.checks.count == 8)
    #expect(report.check(.beep)?.outcome == .skipped)

  }

  @Test func failsALinkThatsMissingTheDevicesRecord() async throws {

    let modem: InMemoryModem = await linkedPlug()
    await modem.setDatabase([:], of: Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let links: SelfTestCheck = try #require(report.check(.modemLinks))

    #expect(links.outcome == .failed)
    #expect(links.detail.contains("the device's responder record for group 0"))
    #expect(links.fixes == [.link, .checkSignal])
    #expect(report.outcome == .failed)

  }

  @Test func failsADatabaseWithARecordWhoseChecksumFailed() async throws {

    let modem: InMemoryModem = await linkedPlug()
    await modem.setDamaged(true, record: 0x0FFF, of: Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let database: SelfTestCheck = try #require(report.check(.linkDatabase))

    #expect(database.outcome == .failed)
    #expect(database.fixes == [.readAgain, .checkSignal])

  }

  @Test func warnsOfADeviceTheCatalogDoesntDescribe() async throws {

    let modem: InMemoryModem = await linkedPlug()
    await modem.setIdentity(SetButtonPressed(sender: Example.plug, role: .responder, category: 0x02, subcategory: 0x55, firmwareVersion: 0x41))

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let catalog: SelfTestCheck = try #require(report.check(.catalog))

    #expect(catalog.outcome == .warning)
    #expect(catalog.fixes == [.updateCatalog])
    #expect(report.productName == nil)

  }

  @Test func warnsOfARecordForADeviceTheModemIsntLinkedTo() async throws {

    let modem: InMemoryModem = await linkedPlug()
    let gone = InsteonAddress(0x0E, 0x0E, 0x0E)
    await modem.setDatabase([0x0FFF: responds(to: modemAddress), 0x0FF7: responds(to: gone, group: 0x02)], of: Example.plug)

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest()
    let leftovers: SelfTestCheck = try #require(report.check(.leftoverRecords))

    #expect(leftovers.outcome == .warning)
    #expect(leftovers.fixes == [.reviewRecords([gone])])
    #expect(report.outcome == .warning)

  }

  // MARK: - The catalog's legs

  @Test func checksEachLegTheCatalogGives() async throws {

    let module: InsteonAddress = HubLinkingExample.module
    let identity: ReportedIdentity = HubLinkingExample.moduleIdentity
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: module)
    await modem.setIdentity(SetButtonPressed(
      sender: module,
      role: .responder,
      category: identity.category,
      subcategory: identity.subcategory,
      firmwareVersion: 0x41
    ))
    // The modem controls the module in group 0, and responds to its group 1.
    await modem.setModemRecords([controls(module, group: 0x00), responds(to: module, group: 0x01)])
    await modem.setDatabase([
      0x0FFF: responds(to: modemAddress, group: 0x00),
      0x0FF7: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: modemAddress)
    ], of: module)

    let report: SelfTestReport = try await network(modem, catalog: HubLinkingExample.catalog).device(module).selfTest()
    let links: SelfTestCheck = try #require(report.check(.modemLinks))

    #expect(links.outcome == .passed)
    #expect(links.detail.contains("2 links the Insteon device catalog gives"))
    #expect(report.checklist == [.pressButton(group: 1), .powerCycle])

  }

  @Test func failsALegMissingTheModemsRecord() {

    let legs: [HubLinkingLeg] = [
      HubLinkingLeg(device: Example.plug, index: 0, count: 2, modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01),
      HubLinkingLeg(device: Example.plug, index: 1, count: 2, modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
    ]
    let deviceRecords: [LinkRecord] = [
      LinkRecord(isController: false, isInUse: true, group: 0x00, address: modemAddress, data: [0, 0, 0]),
      LinkRecord(isController: true, isInUse: true, group: 0x01, address: modemAddress, data: [0, 0, 0])
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

    #expect(check.outcome == .failed)
    #expect(check.detail.contains("the modem's responder record for group 1"))
    #expect(!check.detail.contains("controller record for group 0"))

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

  func reading(flags: UInt8?) -> DeviceSettingsReading {

    let commands: CommandSet = Self.lockedCommands

    return DeviceSettingsReading(
      productName: nil,
      commandSet: commands,
      items: commands.settingItems,
      operatingFlags: flags.map { (byte: UInt8) -> [OperatingFlagsRequest: UInt8] in [.operatingFlags: byte] } ?? [:],
      values: [:],
      buttons: [0x01]
    )

  }

  @Test func warnsOfAProgrammingLockThatsOn() {

    let check: SelfTestCheck = Device.flagsCheck(reading(flags: 0x03))

    #expect(check.outcome == .warning)
    #expect(check.detail.contains("Programming lock is on"))
    #expect(check.fixes == [.turnOffProgrammingLock])

  }

  @Test func passesFlagsThatNeitherLockNorCutOff() {

    let check: SelfTestCheck = Device.flagsCheck(reading(flags: 0x02))

    #expect(check.outcome == .passed)
    #expect(check.detail.hasPrefix("2 operating flags read"))

  }

  @Test func warnsWhenNoFlagIsReported() {

    let check: SelfTestCheck = Device.flagsCheck(reading(flags: nil))

    #expect(check.outcome == .warning)
    #expect(check.fixes == [.readAgain])

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
    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: relay)
    await modem.setIdentity(SetButtonPressed(sender: relay, role: .responder, category: 0x02, subcategory: 0x60, firmwareVersion: 0x45))
    await modem.setLevel(0xFF, of: relay)
    await modem.setModemRecords([controls(relay)])
    await modem.setDatabase([0x0FFF: responds(to: modemAddress)], of: relay)
    let sent = SentMessages()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .standardRequest(message) = operation {

        sent.append(message)

      }

    }
    let device: Device = network(modem, catalog: Self.beepingCatalog).device(relay)

    let reading: SelfTestReport = try await device.selfTest()

    #expect(reading.check(.beep) == nil)
    #expect(!sent.all.contains { (message: StandardMessage) -> Bool in message.command.command1 == 0x30 })

    let actuated: SelfTestReport = try await device.selfTest(SelfTestOptions(actuates: true))

    #expect(actuated.check(.beep)?.outcome == .passed)
    #expect(sent.all.contains { (message: StandardMessage) -> Bool in message.command.command1 == 0x30 })
    // Beep leaves the load as it was, and nothing else is sent that changes it.
    #expect(await modem.levels[relay] == 0xFF)
    #expect(!sent.all.contains { (message: StandardMessage) -> Bool in [0x11, 0x13].contains(message.command.command1) })

  }

  @Test func sendsNothingWhenTheCatalogDoesntListBeep() async throws {

    let modem: InMemoryModem = await linkedPlug()
    let sent = SentMessages()
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .standardRequest(message) = operation {

        sent.append(message)

      }

    }

    let report: SelfTestReport = try await network(modem).device(Example.plug).selfTest(SelfTestOptions(actuates: true))

    #expect(report.check(.beep)?.outcome == .skipped)
    #expect(!sent.all.contains { (message: StandardMessage) -> Bool in message.command.command1 == 0x30 })

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
