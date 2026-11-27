import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol
@testable import InsteonCore

/// Planning a scene's members from the cached ALL-Link databases and the catalog, with nothing sent.
/// Every product here is made up.
@Suite(.timeLimit(.minutes(1)))
struct SceneMembershipPlanTests {

  let modem = InsteonAddress(0x11, 0x22, 0x33)
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let fan = InsteonAddress(0x4D, 0x5E, 0x6F)
  let sensor = InsteonAddress(0x7A, 0x8B, 0x9C)

  // MARK: A made-up catalog

  private static let dimmer = ReportedIdentity(category: 0x01, subcategory: 0x01, firmwareVersion: 0x45)
  private static let switchIdentity = ReportedIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x45)
  private static let sensorIdentity = ReportedIdentity(category: 0x03, subcategory: 0x01, firmwareVersion: 0x45)
  private static let plainIdentity = ReportedIdentity(category: 0x01, subcategory: 0x03, firmwareVersion: 0x45)
  private static let olderIdentity = ReportedIdentity(category: 0x01, subcategory: 0x04, firmwareVersion: 0x45)
  private static let unconfirmedIdentity = ReportedIdentity(category: 0x01, subcategory: 0x05, firmwareVersion: 0x45)
  private static let limitedIdentity = ReportedIdentity(category: 0x01, subcategory: 0x06, firmwareVersion: 0x45)
  private static let twoGroupIdentity = ReportedIdentity(category: 0x01, subcategory: 0x07, firmwareVersion: 0x45)
  private static let strangerIdentity = ReportedIdentity(category: 0x09, subcategory: 0x09, firmwareVersion: 0x45)

  private static let commands = CommandSet(
    id: "exampleScene",
    name: "Example scene",
    summary: "Made-up group types for scene members.",
    groupTypes: [
      GroupType(
        name: "load",
        label: "Load",
        kind: .dimmer,
        linkData: GroupType.LinkData(responder: [
          LinkDataByte(position: 1, name: "onLevel", summary: "The on-level."),
          LinkDataByte(position: 2, name: "rampRate", summary: "The ramp rate."),
          LinkDataByte(position: 3, name: "button", summary: "The device's own group.", isPerGroup: true)
        ])
      ),
      GroupType(
        name: "switchLoad",
        label: "Load",
        kind: .relay,
        linkData: GroupType.LinkData(responder: [
          LinkDataByte(position: 1, name: "onLevel", summary: "On or off.", range: 0x00...0xFF),
          LinkDataByte(position: 3, name: "button", summary: "The device's own group.", isPerGroup: true)
        ])
      ),
      GroupType(
        name: "limitedLoad",
        label: "Load",
        kind: .dimmer,
        linkData: GroupType.LinkData(responder: [
          LinkDataByte(position: 1, name: "onLevel", summary: "The on-level, as a percentage.", range: 0x00...0x64),
          LinkDataByte(position: 3, name: "button", summary: "The device's own group.", isPerGroup: true)
        ])
      ),
      GroupType(name: "plainLoad", label: "Load", kind: .dimmer)
    ]
  )

  private static func profile(_ model: ProductModel, _ identity: ReportedIdentity, type: SettingName, role: DeviceProfile.LinkRole = .responder, engines: [DeviceEngine] = []) -> DeviceProfile {

    DeviceProfile(
      model: model,
      name: "Example \(model)",
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      engines: engines,
      commandSets: [CommandSetEntry(commandSet: "exampleScene", category: identity.category, subcategory: identity.subcategory)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: role, type: type)]
    )

  }

  private static let catalog = DeviceCatalog(
    profiles: [
      profile("9601", dimmer, type: "load", engines: [DeviceEngine(engine: .i2cs, category: dimmer.category, subcategory: dimmer.subcategory)]),
      profile("9602", switchIdentity, type: "switchLoad", engines: [DeviceEngine(engine: .i2cs, category: switchIdentity.category, subcategory: switchIdentity.subcategory)]),
      profile("9603", sensorIdentity, type: "load", role: .controller, engines: [DeviceEngine(engine: .i2cs, category: sensorIdentity.category, subcategory: sensorIdentity.subcategory)]),
      profile("9604", plainIdentity, type: "plainLoad", engines: [DeviceEngine(engine: .i2cs, category: plainIdentity.category, subcategory: plainIdentity.subcategory)]),
      profile("9605", olderIdentity, type: "load", engines: [DeviceEngine(engine: .i2, category: olderIdentity.category, subcategory: olderIdentity.subcategory)]),
      profile("9606", unconfirmedIdentity, type: "load"),
      DeviceProfile(
        model: "9608",
        name: "Example 9608",
        identities: [DeviceIdentity(category: twoGroupIdentity.category, subcategory: twoGroupIdentity.subcategory)],
        engines: [DeviceEngine(engine: .i2cs, category: twoGroupIdentity.category, subcategory: twoGroupIdentity.subcategory)],
        commandSets: [CommandSetEntry(commandSet: "exampleScene", category: twoGroupIdentity.category, subcategory: twoGroupIdentity.subcategory)],
        groups: [
          DeviceProfile.Group(number: 1, name: "Button 1", role: .responder, type: "load"),
          DeviceProfile.Group(number: 2, name: "Button 2", role: .responder, type: "load"),
          DeviceProfile.Group(number: 3, name: "Button 3", role: .controller, type: "load")
        ]
      ),
      profile("9607", limitedIdentity, type: "limitedLoad", engines: [DeviceEngine(engine: .i2cs, category: limitedIdentity.category, subcategory: limitedIdentity.subcategory)])
    ],
    commandSets: [commands]
  )

  /// What the made-up modem's own records hold: Data 1 through Data 3 of a controller record.
  private static let modemData = ModemLinkData(controller: [ModemLinkDataByte(position: 1, name: "fixed", summary: "Always 0x01.", value: 0x01)])

  // MARK: Cached databases

  private func record(_ role: BackupRecordRole, group: UInt8, _ address: InsteonAddress, data: [UInt8] = [0xFF, 0x1F, 0x01], memory: UInt16? = nil) -> BackupRecord {

    BackupRecord(state: .inUse, role: role, group: group, address: address, data: data, memoryAddress: memory)

  }

  /// A device's cached database: the records from 0x0FFF down, some free slots, then the end.
  private func slots(_ records: [BackupRecord], free: Int = 1) -> [BackupRecord] {

    var all: [BackupRecord] = []
    var address: UInt16 = 0x0FFF

    for var held in records {

      held.memoryAddress = address
      all.append(held)
      address -= 8

    }

    for _ in 0..<free {

      all.append(BackupRecord(state: .free, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: address))
      address -= 8

    }

    all.append(BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: address))

    return all

  }

  private func device(_ address: InsteonAddress, _ identity: ReportedIdentity?, engine: BackupEngine? = .i2cs, records: [BackupRecord]?) -> BackupDevice {

    guard let records else {

      return BackupDevice(address: address, identity: identity.map(BackupIdentity.init), engine: engine, unreadable: BackupUnreadable(reason: .notCached))

    }

    return BackupDevice(address: address, identity: identity.map(BackupIdentity.init), engine: engine, allLinkDatabase: BackupDatabase(delta: 0x01, records: records))

  }

  private func backup(modemRecords: [BackupRecord]?, _ devices: [BackupDevice]) -> NetworkBackup {

    let held: BackupModem = modemRecords.map { BackupModem(address: modem, allLinkDatabase: $0) } ?? BackupModem(address: modem, unreadable: BackupUnreadable(reason: .notCached))

    return NetworkBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .service, modem: held, devices: devices)

  }

  private func registered(_ identities: [InsteonAddress: ReportedIdentity]) async -> [InsteonAddress: RegisteredDevice] {

    let registry = DeviceRegistry(catalog: Self.catalog, snapshot: DeviceRegistrySnapshot(identities: identities))
    var found: [InsteonAddress: RegisteredDevice] = [:]

    for address in identities.keys {

      found[address] = await registry.device(address)

    }

    return found

  }

  private func plan(
    _ change: SceneMembershipChange,
    modemRecords: [BackupRecord]? = [],
    lampRecords: [BackupRecord]? = nil,
    identities: [InsteonAddress: ReportedIdentity]? = nil
  ) async -> SceneMembershipPlan {

    let known: [InsteonAddress: ReportedIdentity] = identities ?? [lamp: Self.dimmer]
    let held: [BackupRecord]? = lampRecords ?? slots([record(.responder, group: 9, modem)])
    let backup = backup(modemRecords: modemRecords, [device(lamp, known[lamp], records: held)])

    return SceneMembershipPlanner.plan(change, from: backup, devices: await registered(known), modemLinkData: Self.modemData)

  }

  private func add(_ address: InsteonAddress, onLevel: UInt8? = 0xFF, rampRate: UInt8? = 0x1F, group: UInt8? = nil) -> SceneMembershipChange.Addition {

    SceneMembershipChange.Addition(device: address, onLevel: onLevel, rampRate: rampRate, group: group)

  }

  private func change(_ additions: [SceneMembershipChange.Addition] = [], remove: [InsteonAddress] = [], removeGroups: [SceneMembershipChange.Removal] = [], scene: UInt8 = 3) -> SceneMembershipChange {

    SceneMembershipChange(scene: scene, additions: additions, removals: remove.map { SceneMembershipChange.Removal(device: $0) } + removeGroups)!

  }

  // MARK: Adding

  @Test func addsTheMembersResponderRecordThenTheModemsControllerRecordWithTheCatalogsDataBytes() async throws {

    let plan = await plan(change([add(lamp)]))

    #expect(plan.isApplicable)
    #expect(plan.steps.map(\.kind) == [.addDeviceRecord, .addModemRecord])
    #expect(plan.steps.map(\.endpoint) == [.device(lamp), .modem])

    let deviceRecord = plan.steps[0].record
    #expect(deviceRecord.isController == false)
    #expect(deviceRecord.isInUse)
    #expect(deviceRecord.group == 3)
    #expect(deviceRecord.address == modem)
    // The on-level and ramp rate asked for, and the device's own group, which the catalog marks per group.
    #expect(deviceRecord.data == [0xFF, 0x1F, 0x01])
    // The slot the cached database shows free, not the end.
    #expect(deviceRecord.memoryAddress == 0x0FF7)

    let modemRecord = plan.steps[1].record
    #expect(modemRecord.isController)
    #expect(modemRecord.group == 3)
    #expect(modemRecord.address == lamp)
    #expect(modemRecord.data == [0x01, 0x00, 0x00])
    #expect(modemRecord.memoryAddress == nil)

  }

  @Test func writesTheAskedLevelAndRampRateIntoTheRecord() async throws {

    let plan = await plan(change([add(lamp, onLevel: 0x80, rampRate: 0x0A)]))

    #expect(plan.steps.first?.record.data == [0x80, 0x0A, 0x01])

  }

  @Test func moveTheEndOfTheDatabaseDownFirstWhenNoSlotIsFree() async throws {

    let full = slots([record(.responder, group: 9, modem)], free: 0)
    let plan = await plan(change([add(lamp)]), lampRecords: full)

    #expect(plan.steps.map(\.kind) == [.markEndOfDatabase, .addDeviceRecord, .addModemRecord])
    // The record below the end becomes the new end, then the old end's slot takes the record.
    #expect(plan.steps[0].record.memoryAddress == 0x0FEF)
    #expect(plan.steps[1].record.memoryAddress == 0x0FF7)
    #expect(plan.steps[0].risks == [.movesEndOfDatabase])

  }

  @Test func refusesAMemberWhoseDatabaseHasNoRoomForTheRecord() async throws {

    let lowest = [BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0307)]
    let plan = await plan(change([add(lamp)]), lampRecords: [record(.responder, group: 9, modem, memory: 0x0FFF)] + lowest)

    #expect(plan.refusals.map(\.code) == [.databaseFull])
    #expect(plan.refusals.first?.device == lamp)
    #expect(plan.steps.isEmpty)
    #expect(!plan.isApplicable)

  }

  @Test func givesNoStepForAMemberThatIsAlreadyInTheSceneWithTheSameRecord() async throws {

    let plan = await plan(
      change([add(lamp)]),
      modemRecords: [record(.controller, group: 3, lamp, data: [0x01, 0x00, 0x00])],
      lampRecords: slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x01])])
    )

    #expect(plan.steps.isEmpty)
    #expect(plan.isEmpty)
    #expect(plan.warnings.map(\.code) == [.alreadyMember])
    #expect(plan.requiredConsent == nil)

  }

  @Test func listsAChangedLevelAsAnUpdateInPlaceAndRefusesItAsNotYetSupported() async throws {

    let plan = await plan(
      change([add(lamp, onLevel: 0x80)]),
      modemRecords: [record(.controller, group: 3, lamp, data: [0x01, 0x00, 0x00])],
      lampRecords: slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x01])])
    )

    #expect(plan.steps.map(\.kind) == [.updateDeviceRecord])
    #expect(plan.steps.first?.isUpdateInPlace == true)
    #expect(plan.steps.first?.record.data == [0x80, 0x1F, 0x01])
    #expect(plan.steps.first?.record.memoryAddress == 0x0FFF)
    #expect(plan.refusals.map(\.code) == [.notYetSupported])
    #expect(!plan.isApplicable)
    #expect(plan.requiredConsent == nil)

  }

  @Test func saysWhatIsTrueWhenAChangedLevelComesWithAMissingModemRecord() async throws {

    let plan = await plan(
      change([add(lamp, onLevel: 0x80)]),
      lampRecords: slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x01])])
    )
    let warning = try #require(plan.warnings.first)

    #expect(plan.steps.map(\.kind) == [.updateDeviceRecord, .addModemRecord])
    #expect(plan.refusals.map(\.code) == [.notYetSupported])
    #expect(plan.warnings.map(\.code) == [.halfLinkCompleted])
    // The device's record is not completed by the plan: it holds other bytes, and the rewrite is refused.
    #expect(warning.detail?.contains("on-level or ramp rate") == true)
    #expect(warning.detail?.contains("modem's record is added") == true)

  }

  @Test func addsOnlyTheMissingHalfOfALinkAndSaysSo() async throws {

    let plan = await plan(
      change([add(lamp)]),
      modemRecords: [record(.controller, group: 3, lamp, data: [0x01, 0x00, 0x00])]
    )

    #expect(plan.steps.map(\.kind) == [.addDeviceRecord])
    #expect(plan.warnings.map(\.code) == [.halfLinkCompleted])

  }

  @Test func neverPlansTheReservedGroups() {

    #expect(SceneMembershipChange(scene: 0, additions: [], removals: [.init(device: lamp)]) == nil)
    #expect(SceneMembershipChange(scene: 255, additions: [], removals: [.init(device: lamp)]) == nil)
    #expect(SceneMembershipChange(scene: 1, additions: [], removals: [.init(device: lamp)]) != nil)
    #expect(SceneMembershipChange(scene: 254, additions: [], removals: [.init(device: lamp)]) != nil)

  }

  // MARK: Removing

  @Test func removesTheModemsRecordFirstAndTheMembersLast() async throws {

    let plan = await plan(
      change(remove: [lamp]),
      modemRecords: [record(.controller, group: 3, lamp), record(.controller, group: 4, lamp)],
      lampRecords: slots([record(.responder, group: 3, modem), record(.responder, group: 4, modem)])
    )

    #expect(plan.steps.map(\.kind) == [.removeModemRecord, .removeDeviceRecord])
    #expect(plan.steps.map(\.endpoint) == [.modem, .device(lamp)])
    #expect(plan.steps.allSatisfy { $0.record.group == 3 && !$0.record.isInUse })
    #expect(plan.steps[1].record.memoryAddress == 0x0FFF)
    // The member keeps its record of the modem for the other scene.
    #expect(plan.steps[1].risks.isEmpty)

  }

  @Test func warnsThatAnI2CSMemberRejectsTheModemOnceItsLastRecordOfTheModemIsRemoved() async throws {

    let plan = await plan(
      change(remove: [lamp]),
      modemRecords: [record(.controller, group: 3, lamp)],
      lampRecords: slots([record(.responder, group: 3, modem)])
    )

    #expect(plan.steps.last?.risks == [.rejectsModemOnceUnlinked])

  }

  @Test func saysAMemberThatIsNotInTheSceneIsNotAndPlansNothingForIt() async throws {

    let plan = await plan(change(remove: [lamp]), lampRecords: slots([record(.responder, group: 9, modem)]))

    #expect(plan.steps.isEmpty)
    #expect(plan.warnings.map(\.code) == [.notAMember])
    #expect(plan.refusals.isEmpty)

  }

  /// A two-group device that is in the scene through both its buttons, and the modem's one record of it.
  private var bothButtons: (modem: [BackupRecord], device: [BackupRecord]) {

    (
      [record(.controller, group: 3, lamp, data: [0x01, 0x00, 0x00])],
      slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x01]), record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x02]), record(.responder, group: 9, modem)])
    )

  }

  @Test func removesEveryRecordOfADeviceInTheSceneWhenNoGroupIsNamed() async throws {

    let held = bothButtons
    let plan = await keypadPlan(change(remove: [lamp]), modemRecords: held.modem, keypadRecords: held.device)

    #expect(plan.steps.map(\.kind) == [.removeModemRecord, .removeDeviceRecord, .removeDeviceRecord])
    #expect(plan.steps.compactMap(\.record.memoryAddress) == [0x0FFF, 0x0FF7])
    // The device keeps its record of the modem for the other group, so only the last write says so.
    #expect(plan.steps.map(\.risks) == [[], [], []])
    #expect(plan.isApplicable)

  }

  @Test func removesOnlyTheRecordOfTheGroupNamedAndKeepsTheModemsWhileAnotherGroupRemains() async throws {

    let held = bothButtons
    let plan = await keypadPlan(change(removeGroups: [.init(device: lamp, group: 2)]), modemRecords: held.modem, keypadRecords: held.device)

    #expect(plan.steps.map(\.kind) == [.removeDeviceRecord])
    #expect(plan.steps.first?.record.memoryAddress == 0x0FF7)
    #expect(plan.steps.first?.record.data == [0xFF, 0x1F, 0x02])
    #expect(plan.warnings.isEmpty)

  }

  @Test func removesTheModemsRecordWithTheLastGroupOfTheDeviceInTheScene() async throws {

    let held = bothButtons
    let plan = await keypadPlan(change(removeGroups: [.init(device: lamp, group: 1), .init(device: lamp, group: 2)]), modemRecords: held.modem, keypadRecords: held.device)

    #expect(plan.steps.map(\.kind) == [.removeModemRecord, .removeDeviceRecord, .removeDeviceRecord])
    #expect(plan.refusals.isEmpty)

  }

  @Test func saysAGroupThatIsNotInTheSceneIsNotAMember() async throws {

    let plan = await keypadPlan(
      change(removeGroups: [.init(device: lamp, group: 2)]),
      modemRecords: [record(.controller, group: 3, lamp)],
      keypadRecords: slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x01]), record(.responder, group: 9, modem)])
    )

    #expect(plan.steps.isEmpty)
    #expect(plan.warnings.map(\.code) == [.notAMember])

  }

  @Test func refusesAGroupToRemoveThatTheCatalogDoesNotGiveTheDevice() async throws {

    let held = bothButtons
    let plan = await keypadPlan(change(removeGroups: [.init(device: lamp, group: 7)]), modemRecords: held.modem, keypadRecords: held.device)

    #expect(plan.refusals.map(\.code) == [.unknownGroup])
    #expect(plan.steps.isEmpty)

  }

  @Test func refusesTheSameRemovalNamedTwiceAndAllNamedWithAGroup() async throws {

    let held = bothButtons
    let twice = await keypadPlan(change(removeGroups: [.init(device: lamp, group: 1), .init(device: lamp, group: 1)]), modemRecords: held.modem, keypadRecords: held.device)
    let overlapping = await keypadPlan(change(remove: [lamp], removeGroups: [.init(device: lamp, group: 1)]), modemRecords: held.modem, keypadRecords: held.device)

    #expect(twice.refusals.map(\.code) == [.duplicateEntry])
    #expect(twice.steps.isEmpty)
    #expect(overlapping.refusals.map(\.code) == [.duplicateEntry])
    #expect(overlapping.steps.isEmpty)

  }

  // MARK: What the cache and the catalog allow

  @Test func refusesADeviceWhoseDatabaseIsNotCachedAndSaysToRefresh() async throws {

    let plan = SceneMembershipPlanner.plan(
      change([add(lamp)]),
      from: backup(modemRecords: [], [device(lamp, Self.dimmer, records: nil)]),
      devices: await registered([lamp: Self.dimmer]),
      modemLinkData: Self.modemData
    )

    #expect(plan.refusals.map(\.code) == [.databaseNotCached])
    #expect(plan.refusals.first?.device == lamp)
    #expect(plan.refusals.first?.detail?.contains("Refresh") == true)
    #expect(plan.steps.isEmpty)

  }

  @Test func refusesEverythingWhenTheModemsDatabaseIsNotCached() async throws {

    let plan = await plan(change([add(lamp)]), modemRecords: nil)

    #expect(plan.refusals.map(\.code) == [.databaseNotCached])
    #expect(plan.refusals.first?.device == nil)
    #expect(plan.steps.isEmpty)

  }

  @Test func refusesADeviceTheServiceHasNoIdentityFor() async throws {

    let plan = await plan(change([add(lamp)]), identities: [:])

    #expect(plan.refusals.map(\.code) == [.notIdentified])

  }

  @Test(arguments: [BackupEngine.i1, .i2])
  func refusesADeviceWithNoIdentityAsNotIdentifiedBeforeJudgingItsEngine(_ engine: BackupEngine) async throws {

    let backup = backup(modemRecords: [], [device(lamp, nil, engine: engine, records: slots([]))])
    let plan = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: [:], modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [.notIdentified])
    #expect(plan.devices.map(\.address) == [lamp])

  }

  @Test func refusesADeviceTheCatalogDoesNotDescribe() async throws {

    let plan = await plan(change([add(lamp)]), identities: [lamp: Self.strangerIdentity])

    #expect(plan.refusals.map(\.code) == [.notInCatalog])

  }

  @Test func refusesAnI1DeviceBecauseItsEngineTakesNoRemoteWrite() async throws {

    let backup = backup(modemRecords: [], [device(lamp, Self.dimmer, engine: .i1, records: slots([]))])
    let plan = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: await registered([lamp: Self.dimmer]), modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [.unsupportedEngine])
    #expect(plan.devices.first?.acceptsRemoteWrite == false)

  }

  @Test func refusesAnI2DeviceTheCatalogDoesNotConfirmRunsI2() async throws {

    let backup = backup(modemRecords: [], [device(lamp, Self.unconfirmedIdentity, engine: .i2, records: slots([]))])
    let plan = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: await registered([lamp: Self.unconfirmedIdentity]), modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [.unsupportedEngine])

  }

  @Test func acceptsAnI2DeviceTheCatalogConfirmsRunsI2() async throws {

    let backup = backup(modemRecords: [], [device(lamp, Self.olderIdentity, engine: .i2, records: slots([]))])
    let plan = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: await registered([lamp: Self.olderIdentity]), modemLinkData: Self.modemData)

    #expect(plan.isApplicable)
    #expect(plan.devices.first?.acceptsRemoteWrite == true)
    #expect(plan.devices.first?.engine == .i2)

  }

  @Test func refusesAnI2CSDeviceWhoseCachedDatabaseHoldsNoRecordOfTheModem() async throws {

    let plan = await plan(change([add(lamp)]), lampRecords: slots([record(.responder, group: 9, fan)]))

    #expect(plan.refusals.map(\.code) == [.rejectsModem])

  }

  @Test func readsARejectedModemReasonAsRejectsModem() async throws {

    let backup = backup(modemRecords: [], [BackupDevice(address: lamp, identity: BackupIdentity(Self.dimmer), engine: .i2cs, unreadable: BackupUnreadable(reason: .rejectedModem))])
    let plan = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: await registered([lamp: Self.dimmer]), modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [.rejectsModem])

  }

  @Test(arguments: [(BackupUnreadableReason.damagedRecords, SceneMembershipFinding.Code.damagedRecords), (.incomplete, .noEndOfDatabase)])
  func carriesAChecksumFailureAndAMissingEndRecordAsRefusals(_ reason: BackupUnreadableReason, _ code: SceneMembershipFinding.Code) async throws {

    let backup = backup(modemRecords: [], [BackupDevice(address: lamp, identity: BackupIdentity(Self.dimmer), engine: .i2cs, unreadable: BackupUnreadable(reason: reason))])
    let plan = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: await registered([lamp: Self.dimmer]), modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [code])

  }

  @Test func refusesACachedDatabaseWithNoEndRecord() async throws {

    let plan = await plan(change([add(lamp)]), lampRecords: [record(.responder, group: 9, modem, memory: 0x0FFF)])

    #expect(plan.refusals.map(\.code) == [.noEndOfDatabase])

  }

  @Test func refusesACachedDatabaseWithAnEndAboveARecordInUseAndPlansNoWrite() async throws {

    let inUse = record(.responder, group: 9, modem, memory: 0x0FFF)
    let end = BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FF7)
    // A record in use below an end, and another end below it: writing to the last end's slot would put an
    // end above a link, so which end the device reads up to isn't known.
    let below = record(.responder, group: 4, fan, memory: 0x0FEF)
    let last = BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FE7)
    let plan = await plan(change([add(lamp)]), lampRecords: [inUse, end, below, last])

    #expect(plan.refusals.map(\.code) == [.unexpectedDatabaseLayout])
    #expect(plan.refusals.first?.device == lamp)
    #expect(plan.steps.isEmpty)

  }

  @Test func refusesACachedDatabaseWhoseFreeSlotIsBelowItsEnd() async throws {

    let inUse = record(.responder, group: 9, modem, memory: 0x0FFF)
    let end = BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FEF)
    let free = BackupRecord(state: .free, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FE7)
    // The slot a plan would write is past the end the device reads up to, and so would never be read.
    let plan = await plan(change([add(lamp)]), lampRecords: [inUse, free, end])

    #expect(plan.refusals.map(\.code) == [.unexpectedDatabaseLayout])
    #expect(plan.steps.isEmpty)

  }

  @Test func refusesACachedDatabaseWhoseRecordsAreNotInDescendingOrder() async throws {

    let records = [
      record(.responder, group: 9, modem, memory: 0x0FF7),
      record(.responder, group: 4, fan, memory: 0x0FFF),
      BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FEF)
    ]
    let plan = await plan(change([add(lamp)]), lampRecords: records)

    #expect(plan.refusals.map(\.code) == [.unexpectedDatabaseLayout])
    #expect(plan.steps.isEmpty)

  }

  @Test func refusesARecordOfTheSceneTooShortToSayWhichGroupItIsForOnAddAndRemove() async throws {

    let held: [BackupRecord] = slots([record(.responder, group: 3, modem, data: [0xFF]), record(.responder, group: 9, modem)])
    let modemRecords: [BackupRecord] = [record(.controller, group: 3, lamp)]
    let add = await keypadPlan(change([add(lamp, group: 2)]), modemRecords: modemRecords, keypadRecords: held)
    let remove = await keypadPlan(change(removeGroups: [.init(device: lamp, group: 2)]), modemRecords: modemRecords, keypadRecords: held)

    #expect(add.refusals.map(\.code) == [.unexpectedDatabaseLayout])
    #expect(add.steps.isEmpty)
    #expect(remove.refusals.map(\.code) == [.unexpectedDatabaseLayout])
    #expect(remove.steps.isEmpty)

  }

  @Test func refusesToRemoveARecordWhoseSlotTheCacheDoesNotGive() async throws {

    let plan = await plan(
      change(remove: [lamp]),
      modemRecords: [record(.controller, group: 3, lamp)],
      lampRecords: [record(.responder, group: 3, modem), record(.responder, group: 9, modem), BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FEF)]
    )

    #expect(plan.refusals.map(\.code) == [.unexpectedDatabaseLayout])
    #expect(plan.steps.isEmpty)

  }

  @Test func refusesAGroupThatCannotRespond() async throws {

    let backup = backup(modemRecords: [], [device(sensor, Self.sensorIdentity, records: slots([record(.responder, group: 9, modem)]))])
    let plan = SceneMembershipPlanner.plan(change([add(sensor)]), from: backup, devices: await registered([sensor: Self.sensorIdentity]), modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [.groupCannotRespond])

  }

  @Test func refusesAMemberWhoseLinkDataTheCatalogDoesNotDescribe() async throws {

    let backup = backup(modemRecords: [], [device(lamp, Self.plainIdentity, records: slots([record(.responder, group: 9, modem)]))])
    let plan = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: await registered([lamp: Self.plainIdentity]), modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [.undescribedLinkData])

  }

  @Test func refusesARampRateForAGroupWhoseRecordHasNone() async throws {

    let backup = backup(modemRecords: [], [device(fan, Self.switchIdentity, records: slots([record(.responder, group: 9, modem)]))])
    let plan = SceneMembershipPlanner.plan(change([add(fan, onLevel: 0xFF, rampRate: 0x1F)]), from: backup, devices: await registered([fan: Self.switchIdentity]), modemLinkData: Self.modemData)

    #expect(plan.refusals.map(\.code) == [.valueNotTaken])
    #expect(plan.refusals.first?.detail?.contains("rampRate") == true)

  }

  @Test func refusesAValueOutsideTheRangeTheCatalogGivesTheByte() async throws {

    let backup = backup(modemRecords: [], [device(lamp, Self.limitedIdentity, records: slots([record(.responder, group: 9, modem)]))])
    let identities: [InsteonAddress: ReportedIdentity] = [lamp: Self.limitedIdentity]
    let outside = SceneMembershipPlanner.plan(change([add(lamp, onLevel: 0x65, rampRate: nil)]), from: backup, devices: await registered(identities), modemLinkData: Self.modemData)
    let inside = SceneMembershipPlanner.plan(change([add(lamp, onLevel: 0x64, rampRate: nil)]), from: backup, devices: await registered(identities), modemLinkData: Self.modemData)

    #expect(outside.refusals.map(\.code) == [.valueOutOfRange])
    #expect(inside.isApplicable)

  }

  @Test func refusesADeviceNamedInBothListsAndPlansNothingForIt() async throws {

    let plan = await plan(change([add(lamp)], remove: [lamp]))

    #expect(plan.refusals.map(\.code) == [.addedAndRemoved])
    #expect(plan.refusals.first?.device == lamp)
    #expect(plan.steps.isEmpty)
    #expect(!plan.isApplicable)

  }

  @Test func refusesTheSameDeviceAndGroupNamedTwiceAndPlansNothingForIt() async throws {

    let plan = await plan(change([add(lamp), add(lamp, onLevel: 0x10)]))

    #expect(plan.refusals.map(\.code) == [.duplicateEntry])
    #expect(plan.refusals.first?.device == lamp)
    #expect(plan.steps.isEmpty)

  }

  @Test func takesAnAdditionWithNoGroupAndOneNamingTheMainGroupAsTheSame() async throws {

    let plan = await keypadPlan(change([add(lamp), add(lamp, group: 1)]))

    #expect(plan.refusals.map(\.code) == [.duplicateEntry])
    #expect(plan.steps.isEmpty)

  }

  @Test func plansTwoGroupsOfOneDeviceEachInASlotOfItsOwnWithTheModemsRecordOnce() async throws {

    let plan = await keypadPlan(change([add(lamp, group: 1), add(lamp, group: 2)]), free: 1)

    #expect(plan.refusals.isEmpty)
    #expect(plan.warnings.isEmpty)
    #expect(plan.steps.map(\.kind) == [.addDeviceRecord, .addModemRecord, .markEndOfDatabase, .addDeviceRecord])
    // The first takes the free slot, the second the end's, with the end marked a slot below first.
    #expect(plan.steps[0].record.memoryAddress == 0x0FF7)
    #expect(plan.steps[0].record.data == [0xFF, 0x1F, 0x01])
    #expect(plan.steps[2].record.memoryAddress == 0x0FE7)
    #expect(plan.steps[3].record.memoryAddress == 0x0FEF)
    #expect(plan.steps[3].record.data == [0xFF, 0x1F, 0x02])

  }

  @Test func refusesAGroupTheCatalogDoesNotGiveTheDevice() async throws {

    let plan = await plan(change([add(lamp, group: 7)]))

    #expect(plan.refusals.map(\.code) == [.unknownGroup])
    #expect(plan.refusals.first?.device == lamp)
    #expect(plan.steps.isEmpty)

  }

  @Test func plansTheGroupAskedForWhenTheCatalogGivesItAndItsOwnGroupIsTheDefault() async throws {

    let backup = backup(modemRecords: [], [device(lamp, Self.twoGroupIdentity, records: slots([record(.responder, group: 9, modem)]))])
    let identities: [InsteonAddress: ReportedIdentity] = [lamp: Self.twoGroupIdentity]
    let second = SceneMembershipPlanner.plan(change([add(lamp, group: 2)]), from: backup, devices: await registered(identities), modemLinkData: Self.modemData)
    let main = SceneMembershipPlanner.plan(change([add(lamp)]), from: backup, devices: await registered(identities), modemLinkData: Self.modemData)
    let controlling = SceneMembershipPlanner.plan(change([add(lamp, group: 3)]), from: backup, devices: await registered(identities), modemLinkData: Self.modemData)

    // The third data byte holds the member's own group.
    #expect(second.steps.first?.record.data == [0xFF, 0x1F, 0x02])
    #expect(main.steps.first?.record.data == [0xFF, 0x1F, 0x01])
    // A group the catalog gives only a controller role can't respond.
    #expect(controlling.refusals.map(\.code) == [.groupCannotRespond])

  }

  @Test func plansAGroupWithNoRampRateWhenNoneIsAsked() async throws {

    let backup = backup(modemRecords: [], [device(fan, Self.switchIdentity, records: slots([record(.responder, group: 9, modem)]))])
    let plan = SceneMembershipPlanner.plan(change([add(fan, onLevel: 0xFF, rampRate: nil)]), from: backup, devices: await registered([fan: Self.switchIdentity]), modemLinkData: Self.modemData)

    #expect(plan.isApplicable)
    #expect(plan.steps.first?.record.data == [0xFF, 0x00, 0x01])

  }

  @Test func fillsAnOnLevelAndRampRateTheRequestLeavesOutWithFullOnAndHalfASecond() async throws {

    let plan = await plan(change([add(lamp, onLevel: nil, rampRate: nil)]))

    #expect(plan.steps.first?.record.data == [0xFF, 0x1C, 0x01])

  }

  // MARK: A device with more than one group

  /// A plan for the two-group device, from the records its database and the modem's hold.
  private func keypadPlan(_ change: SceneMembershipChange, modemRecords: [BackupRecord] = [], keypadRecords: [BackupRecord]? = nil, free: Int = 1) async -> SceneMembershipPlan {

    let held: [BackupRecord] = keypadRecords ?? slots([record(.responder, group: 9, modem)], free: free)
    let backup = backup(modemRecords: modemRecords, [device(lamp, Self.twoGroupIdentity, records: held)])

    return SceneMembershipPlanner.plan(change, from: backup, devices: await registered([lamp: Self.twoGroupIdentity]), modemLinkData: Self.modemData)

  }

  @Test func addsASecondGroupOfAMemberAsAnotherRecordAndNotOverTheFirst() async throws {

    let plan = await keypadPlan(
      change([add(lamp, group: 2)]),
      modemRecords: [record(.controller, group: 3, lamp, data: [0x01, 0x00, 0x00])],
      keypadRecords: slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x01])])
    )

    // The first button's record stays, the second button gets a record of its own, and the modem's
    // record for the device is already there.
    #expect(plan.steps.map(\.kind) == [.addDeviceRecord])
    #expect(plan.steps.first?.record.data == [0xFF, 0x1F, 0x02])
    #expect(plan.steps.first?.record.memoryAddress == 0x0FF7)
    #expect(plan.refusals.isEmpty)
    #expect(plan.warnings.isEmpty)
    #expect(plan.isApplicable)

  }

  @Test func saysAHalfLinkWasCompletedOnlyWhenTheRecordForTheGroupAskedForWasInPlace() async throws {

    let records: [BackupRecord] = slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x01])])
    // Button 1 has its record and the modem has none; button 2 has neither.
    let second = await keypadPlan(change([add(lamp, group: 2)]), keypadRecords: records)
    let first = await keypadPlan(change([add(lamp, group: 1)]), keypadRecords: records)

    #expect(second.steps.map(\.kind) == [.addDeviceRecord, .addModemRecord])
    #expect(second.warnings.isEmpty)
    #expect(first.steps.map(\.kind) == [.addModemRecord])
    #expect(first.warnings.map(\.code) == [.halfLinkCompleted])

  }

  @Test func saysAGroupIsAlreadyAMemberOnlyWhenTheDevicesOwnGroupMatches() async throws {

    let records: [BackupRecord] = slots([record(.responder, group: 3, modem, data: [0xFF, 0x1F, 0x02])])
    let held: [BackupRecord] = [record(.controller, group: 3, lamp, data: [0x01, 0x00, 0x00])]
    let second = await keypadPlan(change([add(lamp, group: 2)]), modemRecords: held, keypadRecords: records)
    let first = await keypadPlan(change([add(lamp, group: 1)]), modemRecords: held, keypadRecords: records)

    #expect(second.steps.isEmpty)
    #expect(second.warnings.map(\.code) == [.alreadyMember])
    // Button 1 isn't in the scene though button 2 is, so it gets its own record and no update.
    #expect(first.steps.map(\.kind) == [.addDeviceRecord])
    #expect(first.steps.first?.record.data == [0xFF, 0x1F, 0x01])
    #expect(first.warnings.isEmpty)

  }

  // MARK: Identity of a plan

  @Test func namesAPlanByAHashOfItsStepsSoTheSameChangeHasTheSameId() async throws {

    let first = await plan(change([add(lamp)]))
    let second = await plan(change([add(lamp)]))
    let other = await plan(change([add(lamp, onLevel: 0x80)]))

    #expect(first.id == second.id)
    #expect(first.id != other.id)
    #expect(first.id.hasPrefix("sha256:"))
    #expect(first.id.count == "sha256:".count + 64)

  }

  @Test func asksForTheLinkingConsentThatNamesThePlanAndChangesWithTheRecordsRead() async throws {

    let first = await plan(change([add(lamp)]))
    // The modem holds one more record, which the steps don't touch.
    let reread = await plan(change([add(lamp)]), modemRecords: [record(.controller, group: 8, fan)])
    let consent = try #require(first.requiredConsent)

    #expect(consent == DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: first.fingerprint))
    #expect(consent.writeLinkRecords)
    // The steps are the same, but one more record was read, so another plan is shown, and the id a
    // service keeps it under is another, so consent for one never meets the other.
    #expect(first.steps == reread.steps)
    #expect(first.id != reread.id)
    #expect(first.fingerprint != reread.fingerprint)
    #expect(first.fingerprint.hasPrefix("sha256:"))

  }

  @Test func changesTheFingerprintWhenAnyFieldOfAStepChanges() throws {

    let record = LinkRecord(isController: false, isInUse: true, group: 3, address: modem, data: [0xFF, 0x1F, 0x01], memoryAddress: 0x0FF7)
    let base = SceneMembershipStep(kind: .addDeviceRecord, endpoint: .device(lamp), record: record)

    func fingerprint(_ step: SceneMembershipStep) -> String {

      SceneMembershipPlan(scene: 3, steps: [step], warnings: [], refusals: [], devices: [], readLines: []).fingerprint

    }

    func changed(_ change: (inout SceneMembershipStep) -> Void) -> String {

      var step = base
      change(&step)

      return fingerprint(step)

    }

    let variants: [String: String] = [
      "kind": changed { $0.kind = .updateDeviceRecord },
      "endpoint": changed { $0.endpoint = .device(fan) },
      "modem endpoint": changed { $0.endpoint = .modem },
      "isController": changed { $0.record.isController = true },
      "isInUse": changed { $0.record.isInUse = false },
      "group": changed { $0.record.group = 4 },
      "address": changed { $0.record.address = fan },
      "data": changed { $0.record.data = [0xFF, 0x1F, 0x02] },
      "memoryAddress": changed { $0.record.memoryAddress = 0x0FEF },
      "no memoryAddress": changed { $0.record.memoryAddress = nil },
      "hasIntactChecksum": changed { $0.record.hasIntactChecksum = false },
      "isEndOfDatabase": changed { $0.record.isEndOfDatabase = true },
      "risks": changed { $0.risks = [.movesEndOfDatabase] }
    ]

    #expect(variants.count == 13)

    for (field, other) in variants {

      #expect(other != fingerprint(base), "\(field) is left out of the fingerprint")

    }

    #expect(Set(variants.values).count == variants.count)

  }

  @Test func sendsNothingBecauseItReadsOnlyWhatItIsGiven() async throws {

    // The planner takes values, so there is nothing to send to: the same inputs give the same plan.
    let first = await plan(change([add(lamp)], remove: []))
    let second = await plan(change([add(lamp)], remove: []))

    #expect(first == second)

  }

}
