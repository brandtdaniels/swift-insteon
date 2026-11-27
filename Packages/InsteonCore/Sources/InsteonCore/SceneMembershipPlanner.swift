import Foundation
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// Plans a scene's members from the ALL-Link databases a service has cached and the Insteon device
/// catalog, and sends nothing.
///
/// The planner takes values and reads no database from hardware, so the plan is only as new as the
/// copies it is given. Applying it reads both databases again and writes nothing if either changed.
public enum SceneMembershipPlanner {

  /// Plans the writes that make a change to a scene's members.
  ///
  /// For each device to add, the plan writes the device's responder record for the scene, with the
  /// on-level, ramp rate and own group the catalog's link data for the device's group gives, and
  /// the modem's controller record for the device. A device already a member with the same record
  /// gets no step. One with another on-level or ramp rate gets an update step in place, which the
  /// plan refuses as ``SceneMembershipFinding/Code/notYetSupported``. For each device to remove, it
  /// deletes the modem's record and clears the device's, the modem's first.
  ///
  /// A device named in both lists is planned for its addition only, and one named twice is planned
  /// once.
  ///
  /// - Parameters:
  ///   - change: What to add and remove.
  ///   - backup: What the service has cached: the modem's address and database, and each device's
  ///     database, engine and identity.
  ///   - devices: The devices the service recorded an identity for, with what the catalog says
  ///     about it.
  ///   - modemLinkData: What the records the modem writes hold, from the catalog's profile of the
  ///     modem, or `nil` for zeros.
  /// - Returns: The plan, which can be refused in part or whole.
  public static func plan(
    _ change: SceneMembershipChange,
    from backup: NetworkBackup,
    devices: [InsteonAddress: RegisteredDevice],
    modemLinkData: ModemLinkData?
  ) -> SceneMembershipPlan {

    var plan: Planning = Planning(change: change)

    guard let modem = backup.modem, let modemRecords = modem.allLinkDatabase else {

      plan.refusals.append(SceneMembershipFinding(code: .databaseNotCached, device: nil, detail: "The modem's ALL-Link database isn't cached. Refresh the scenes to read it."))

      return plan.result

    }

    plan.modem = modem.address
    plan.readLines = modemRecords.filter(\.isInUse).map { (record: BackupRecord) -> String in "modemRecord \(Self.line(record))" }

    var named: Set<InsteonAddress> = []

    for addition in change.additions where named.insert(addition.device).inserted {

      plan.add(addition, backup: backup, registered: devices[addition.device], modemRecords: modemRecords, modemLinkData: modemLinkData)

    }

    for removal in change.removals where named.insert(removal).inserted {

      plan.remove(removal, backup: backup, registered: devices[removal], modemRecords: modemRecords)

    }

    return plan.result

  }

  fileprivate static func line(_ record: BackupRecord) -> String {

    "\(record.state.rawValue) \(record.role.rawValue) \(record.group) \(SceneMembershipPlan.hex(record.address.bytes)) \(SceneMembershipPlan.hex(record.data)) \(record.memoryAddress.map { String(format: "%04X", $0) } ?? "modem")"

  }

}

/// A plan being made.
private struct Planning {

  let change: SceneMembershipChange
  var modem: InsteonAddress = InsteonAddress(0, 0, 0)
  var steps: [SceneMembershipStep] = []
  var warnings: [SceneMembershipFinding] = []
  var refusals: [SceneMembershipFinding] = []
  var devices: [SceneMembershipDevice] = []
  var readLines: [String] = []

  init(change: SceneMembershipChange) {

    self.change = change

  }

  var result: SceneMembershipPlan {

    SceneMembershipPlan(scene: change.scene, steps: steps, warnings: warnings, refusals: refusals, devices: devices, readLines: readLines)

  }

  private var group: AllLinkGroupNumber {

    AllLinkGroupNumber(rawValue: change.scene)

  }

  /// A device that can take the plan's writes: its cached records, and the engine it runs.
  private struct Eligible {

    var records: [BackupRecord]
    var engine: InsteonEngine

  }

  // MARK: Eligibility

  /// Checks that the device's cached database was read whole and that its engine takes a remote
  /// write, and records the device's facts.
  private mutating func eligibility(of address: InsteonAddress, backup: NetworkBackup, registered: RegisteredDevice?) -> Eligible? {

    let held: BackupDevice? = backup.devices.first { (device: BackupDevice) -> Bool in device.address == address }
    let engine: InsteonEngine? = (held?.engine).map(Self.engine) ?? registered?.info.engine
    var fact = SceneMembershipDevice(address: address, product: registered?.info.displayName, engine: engine, acceptsRemoteWrite: false)

    func refuse(_ code: SceneMembershipFinding.Code, _ detail: String? = nil) -> Eligible? {

      devices.append(fact)
      refusals.append(SceneMembershipFinding(code: code, device: address, detail: detail))

      return nil

    }

    guard let held else {

      return refuse(.databaseNotCached, "The service holds no ALL-Link database for this device. Refresh the scenes to read it.")

    }

    guard let database = held.allLinkDatabase else {

      switch held.unreadable?.reason {
      case .rejectedModem:
        return refuse(.rejectsModem, "The device rejected the modem when its database was read.")
      case .damagedRecords:
        return refuse(.damagedRecords, held.unreadable?.detail)
      case .incomplete:
        return refuse(.noEndOfDatabase, "The cached database ended without the record that marks its end. Refresh the scenes to read it again.")
      default:
        return refuse(.databaseNotCached, "The service holds no ALL-Link database for this device. Refresh the scenes to read it.")
      }

    }

    guard database.isComplete else {

      return refuse(.noEndOfDatabase, "The cached database ended without the record that marks its end. Refresh the scenes to read it again.")

    }

    readLines += database.records.map { (record: BackupRecord) -> String in "deviceRecord \(address) \(SceneMembershipPlanner.line(record))" }

    switch engine {
    case .i1, nil:
      return refuse(.unsupportedEngine, "The device's engine takes no database writes.")
    case .i2:
      guard registered?.info.engine == .i2 else {

        return refuse(.unsupportedEngine, "The device reports i2, and the catalog doesn't confirm that it runs i2.")

      }
    case .i2cs:
      // A device linked to the modem has a record of it; an i2CS device with none rejects the modem.
      guard database.records.contains(where: { (record: BackupRecord) -> Bool in record.isInUse && record.address == modem }) else {

        return refuse(.rejectsModem, "The device's cached database holds no record of the modem, and an i2CS device rejects a modem it isn't linked to.")

      }
    }

    fact.acceptsRemoteWrite = true
    devices.append(fact)

    return Eligible(records: database.records, engine: engine ?? .i2cs)

  }

  private static func engine(_ engine: BackupEngine) -> InsteonEngine {

    switch engine {
    case .i1:
      .i1
    case .i2:
      .i2
    case .i2cs:
      .i2cs
    }

  }

  /// What a device's responder record would hold, or why it can't be written.
  private enum ResponderData {

    /// The data bytes, the device's group that answers, and the data byte (1 through 3) that holds
    /// that group, or `nil` when the catalog gives the record no such byte.
    case bytes([UInt8], group: UInt8, groupPosition: Int?)
    case refused(SceneMembershipFinding.Code, String)

  }

  /// Whether a record of the device's is for the device's group `group`: its own-group data byte
  /// says so, or the catalog gives the record none, so the device has the one group.
  private static func isRecord(_ record: BackupRecord, ofGroup group: UInt8, at position: Int?) -> Bool {

    guard let position, record.data.count >= position else {

      return true

    }

    return record.data[position - 1] == group

  }

  // MARK: Adding

  mutating func add(_ addition: SceneMembershipChange.Addition, backup: NetworkBackup, registered: RegisteredDevice?, modemRecords: [BackupRecord], modemLinkData: ModemLinkData?) {

    let address: InsteonAddress = addition.device

    guard let eligible = eligibility(of: address, backup: backup, registered: registered) else {

      return

    }

    func refuse(_ code: SceneMembershipFinding.Code, _ detail: String? = nil) {

      refusals.append(SceneMembershipFinding(code: code, device: address, detail: detail))

    }

    guard let registered else {

      refuse(.notIdentified, "The service has no identity recorded for the device, so the catalog can't say what its record holds.")

      return

    }

    guard registered.info.isInCatalog else {

      refuse(.notInCatalog, "The catalog doesn't describe the identity the device reported.")

      return

    }

    let data: [UInt8]
    let deviceGroup: UInt8
    let groupPosition: Int?

    switch Self.responderData(addition, of: registered) {
    case let .bytes(held, group, position):
      data = held
      deviceGroup = group
      groupPosition = position
    case let .refused(code, detail):
      refuse(code, detail)

      return
    }

    let modemHalf: BackupRecord? = modemRecords.first { (record: BackupRecord) -> Bool in
      record.isInUse && record.role == .controller && record.group == change.scene && record.address == address
    }
    // The device's records of the scene: one for each of its groups that answers it.
    let sceneRecords: [BackupRecord] = eligible.records.filter { (record: BackupRecord) -> Bool in
      record.isInUse && record.role == .responder && record.group == change.scene && record.address == modem
    }
    let deviceHalf: BackupRecord? = sceneRecords.first { (record: BackupRecord) -> Bool in
      Self.isRecord(record, ofGroup: deviceGroup, at: groupPosition)
    }

    var addedHalf: Bool = false

    if let deviceHalf {

      if deviceHalf.data != data {

        steps.append(SceneMembershipStep(kind: .updateDeviceRecord, endpoint: .device(address), record: LinkRecord(isController: false, isInUse: true, group: group, address: modem, data: data, memoryAddress: deviceHalf.memoryAddress)))
        refuse(.notYetSupported, "The device is a member with another on-level or ramp rate. Rewriting a record in use in place isn't made until it has been tried on hardware.")

      }

    } else {

      guard addDeviceRecord(data, to: address, records: eligible.records) else {

        return

      }

      addedHalf = true

    }

    if modemHalf == nil {

      let modemData: [UInt8] = DeviceLinkingCoordinator.modemData(modemLinkData, isController: true, reported: registered.identity)

      steps.append(SceneMembershipStep(kind: .addModemRecord, endpoint: .modem, record: LinkRecord(isController: true, isInUse: true, group: group, address: address, data: modemData)))
      addedHalf = true

      if !sceneRecords.isEmpty {

        warnings.append(SceneMembershipFinding(code: .halfLinkCompleted, device: address, detail: "The device's record was in place and the modem's was missing."))

      }

    } else if addedHalf, sceneRecords.isEmpty {

      // A group added to a device already in the scene by another group is a member's second record, not a half link.
      warnings.append(SceneMembershipFinding(code: .halfLinkCompleted, device: address, detail: "The modem's record was in place and the device's was missing."))

    }

    if modemHalf != nil, deviceHalf != nil, deviceHalf?.data == data {

      warnings.append(SceneMembershipFinding(code: .alreadyMember, device: address))

    }

  }

  /// Adds the steps that write the device's responder record, into a free slot or the end's.
  private mutating func addDeviceRecord(_ data: [UInt8], to address: InsteonAddress, records: [BackupRecord]) -> Bool {

    let record = LinkRecord(isController: false, isInUse: true, group: group, address: modem, data: data)

    if let free = records.first(where: { (held: BackupRecord) -> Bool in held.state == .free && held.memoryAddress != nil }), let slot = free.memoryAddress {

      var written: LinkRecord = record
      written.memoryAddress = slot
      steps.append(SceneMembershipStep(kind: .addDeviceRecord, endpoint: .device(address), record: written))

      return true

    }

    guard let end = records.last?.memoryAddress else {

      refusals.append(SceneMembershipFinding(code: .noEndOfDatabase, device: address, detail: "The cached database holds no address for the record that marks its end."))

      return false

    }

    // The slot below the end becomes the new end before the end's slot is written, so the database
    // always has an end, even if the second write fails.
    guard let newEnd = DeviceDatabaseLayout.address(below: end) else {

      refusals.append(SceneMembershipFinding(code: .databaseFull, device: address, detail: "The device's database has room for 0 more records, and 1 is needed."))

      return false

    }

    steps.append(SceneMembershipStep(
      kind: .markEndOfDatabase,
      endpoint: .device(address),
      record: LinkRecord(isController: false, isInUse: false, group: AllLinkGroupNumber(rawValue: 0), address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: newEnd, isEndOfDatabase: true),
      risks: [.movesEndOfDatabase]
    ))

    var written: LinkRecord = record
    written.memoryAddress = end
    steps.append(SceneMembershipStep(kind: .addDeviceRecord, endpoint: .device(address), record: written))

    return true

  }

  /// The three data bytes of the device's responder record, from what the catalog says its group's
  /// record holds and what the client asked for.
  private static func responderData(_ addition: SceneMembershipChange.Addition, of registered: RegisteredDevice) -> ResponderData {

    func refuse(_ code: SceneMembershipFinding.Code, _ detail: String) -> ResponderData {

      .refused(code, detail)

    }

    let description: DeviceDescription = registered.deviceDescription

    let chosen: DeviceProfile.Group?

    if let asked = addition.group {

      chosen = description.profile?.groups.first { (group: DeviceProfile.Group) -> Bool in group.number.rawValue == asked }

      guard chosen != nil else {

        return refuse(.unknownGroup, "The catalog gives the device no group \(asked).")

      }

    } else {

      chosen = description.mainGroup

    }

    guard let main = chosen, let type = description.groupType(forGroup: main.number), !type.linkData.responder.isEmpty else {

      return refuse(.undescribedLinkData, "The catalog doesn't say what the data bytes of the device's responder record hold.")

    }

    guard main.role != .controller else {

      return refuse(.groupCannotRespond, "The device's group only controls, so it takes no part in a scene as a member.")

    }

    var data: [UInt8] = [0x00, 0x00, 0x00]
    var used: Set<String> = []
    var groupPosition: Int?

    for byte in type.linkData.responder where (1...3).contains(byte.position) {

      let name: String = byte.name.rawValue
      let asked: UInt8?

      switch name {
      case "onLevel":
        asked = addition.onLevel
      case "rampRate":
        asked = addition.rampRate
      default:
        asked = nil
      }

      if let value = byte.value {

        if let asked, asked != value {

          return refuse(.valueNotTaken, "The catalog fixes \(name) at \(value) for this group.")

        }

        data[byte.position - 1] = value

      } else if byte.isPerGroup {

        data[byte.position - 1] = main.number.rawValue
        groupPosition = byte.position

      } else if name == "onLevel" || name == "rampRate" {

        let value: UInt8 = asked ?? (name == "onLevel" ? DeviceLinkingCoordinator.fullOnLevel : DeviceLinkingCoordinator.halfSecondRampRate)

        if let range = byte.range, !range.contains(value) {

          return refuse(.valueOutOfRange, "\(name) \(value) is outside \(range.lowerBound) through \(range.upperBound), the range the catalog gives.")

        }

        data[byte.position - 1] = value

      } else {

        return refuse(.unknownLinkDataByte, "The catalog gives no value to write for the data byte \(name).")

      }

      used.insert(name)

    }

    if addition.onLevel != nil, !used.contains("onLevel") {

      return refuse(.valueNotTaken, "The device's record has no onLevel byte, so an on-level can't be set.")

    }

    if addition.rampRate != nil, !used.contains("rampRate") {

      return refuse(.valueNotTaken, "The device's record has no rampRate byte, so a ramp rate can't be set.")

    }

    return .bytes(data, group: main.number.rawValue, groupPosition: groupPosition)

  }

  // MARK: Removing

  mutating func remove(_ address: InsteonAddress, backup: NetworkBackup, registered: RegisteredDevice?, modemRecords: [BackupRecord]) {

    guard let eligible = eligibility(of: address, backup: backup, registered: registered) else {

      return

    }

    let modemHalf: BackupRecord? = modemRecords.first { (record: BackupRecord) -> Bool in
      record.isInUse && record.role == .controller && record.group == change.scene && record.address == address
    }
    let deviceHalf: BackupRecord? = eligible.records.first { (record: BackupRecord) -> Bool in
      record.isInUse && record.role == .responder && record.group == change.scene && record.address == modem
    }

    guard modemHalf != nil || deviceHalf != nil else {

      warnings.append(SceneMembershipFinding(code: .notAMember, device: address))

      return

    }

    // The modem's record goes first, so the device keeps its record of the modem until its last write.
    if let modemHalf {

      steps.append(SceneMembershipStep(kind: .removeModemRecord, endpoint: .modem, record: LinkRecord(isController: true, isInUse: false, group: group, address: address, data: modemHalf.data)))

    }

    if let deviceHalf {

      let otherLinks: Int = eligible.records.filter { (record: BackupRecord) -> Bool in
        record.isInUse && record.address == modem && record != deviceHalf
      }.count
      let risks: [SceneMembershipStep.Risk] = eligible.engine == .i2cs && otherLinks == 0 ? [.rejectsModemOnceUnlinked] : []

      steps.append(SceneMembershipStep(kind: .removeDeviceRecord, endpoint: .device(address), record: LinkRecord(isController: false, isInUse: false, group: group, address: modem, data: deviceHalf.data, memoryAddress: deviceHalf.memoryAddress), risks: risks))

    }

  }

}
