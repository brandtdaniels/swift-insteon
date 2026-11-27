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
  /// For each device and group to add, the plan writes the device's responder record for the scene, with
  /// the on-level, ramp rate and own group the catalog's link data for the device's group gives, and
  /// the modem's controller record for the device, once for the device however many groups it has in
  /// the scene. A group already a member with the same record gets no step. One with another on-level
  /// or ramp rate gets an update step in place, which the plan refuses as
  /// ``SceneMembershipFinding/Code/notYetSupported``. For each device to remove, it clears the
  /// device's records of the scene, or the one for the group named, and deletes the modem's record when
  /// no group of the device stays in the scene, the modem's first.
  ///
  /// A device named in both lists, or for the same group twice, is refused and planned for nothing.
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

    guard let modem = backup.modem, let modemRecords = modem.allLinkDatabase else {

      let refusal = SceneMembershipFinding(code: .databaseNotCached, device: nil, detail: "The modem's ALL-Link database isn't cached. Refresh the scenes to read it.")

      return SceneMembershipPlan(scene: change.scene, steps: [], warnings: [], refusals: [refusal], devices: [], readLines: [])

    }

    let held: [InsteonAddress: BackupDevice] = Dictionary(backup.devices.map { (device: BackupDevice) -> (InsteonAddress, BackupDevice) in (device.address, device) }, uniquingKeysWith: { (first: BackupDevice, _: BackupDevice) -> BackupDevice in first })
    var plan: Planning = Planning(change: change, modem: modem.address, modemRecords: modemRecords, held: held)

    // A device named in both lists, or twice for the same group, is refused whole: which of the entries
    // is meant isn't clear, so none of them is planned.
    var refused: Set<InsteonAddress> = []

    for device in change.additions.map(\.device) where change.removals.map(\.device).contains(device) && refused.insert(device).inserted {

      plan.refusals.append(SceneMembershipFinding(code: .addedAndRemoved, device: device, detail: "The change adds the device and removes it."))

    }

    var counts: [AdditionKey: Int] = [:]

    for addition in change.additions {

      counts[Self.key(of: addition, registered: devices[addition.device]), default: 0] += 1

    }

    var reported: Set<AdditionKey> = []

    for addition in change.additions {

      let key: AdditionKey = Self.key(of: addition, registered: devices[addition.device])

      guard !refused.contains(addition.device) else {

        continue

      }

      if counts[key, default: 0] > 1 {

        if reported.insert(key).inserted {

          plan.refusals.append(SceneMembershipFinding(code: .duplicateEntry, device: addition.device, detail: "The change adds the device's group more than once."))

        }

        continue

      }

      plan.add(addition, registered: devices[addition.device], modemLinkData: modemLinkData)

    }

    // A device's removals: each group once, or all of its records once. Naming one twice, or all of it and
    // a group, is refused for the device.
    var order: [InsteonAddress] = []
    var asked: [InsteonAddress: [UInt8?]] = [:]

    for removal in change.removals where !refused.contains(removal.device) {

      if asked[removal.device] == nil {

        order.append(removal.device)

      }

      asked[removal.device, default: []].append(removal.group)

    }

    for device in order {

      let groups: [UInt8?] = asked[device] ?? []

      guard Set(groups).count == groups.count, groups.count == 1 || !groups.contains(nil) else {

        plan.refusals.append(SceneMembershipFinding(code: .duplicateEntry, device: device, detail: "The change removes the same group of the device more than once."))

        continue

      }

      plan.remove(device, groups: groups.contains(nil) ? nil : groups.compactMap { $0 }, registered: devices[device])

    }

    return plan.result

  }

  /// What names an addition: the device and the group of it that answers, which is its main group when the
  /// request names none and the catalog says which that is.
  private struct AdditionKey: Hashable {

    let device: InsteonAddress
    let group: UInt8?

  }

  private static func key(of addition: SceneMembershipChange.Addition, registered: RegisteredDevice?) -> AdditionKey {

    AdditionKey(device: addition.device, group: addition.group ?? registered?.deviceDescription.mainGroup?.number.rawValue)

  }

  fileprivate static func line(_ record: BackupRecord) -> String {

    "\(record.state.rawValue) \(record.role.rawValue) \(record.group) \(SceneMembershipPlan.hex(record.address.bytes)) \(SceneMembershipPlan.hex(record.data)) \(record.memoryAddress.map { String(format: "%04X", $0) } ?? "modem")"

  }

}

/// A plan being made.
private struct Planning {

  let change: SceneMembershipChange
  let modem: InsteonAddress
  var steps: [SceneMembershipStep] = []
  var warnings: [SceneMembershipFinding] = []
  var refusals: [SceneMembershipFinding] = []
  var devices: [SceneMembershipDevice] = []
  var readLines: [String] = []

  /// The modem's records, with the controller records the plan adds.
  private var modemRecords: [BackupRecord]

  /// The cached devices, by address.
  private let held: [InsteonAddress: BackupDevice]

  /// The records of each device the plan could write to, with the records the plan adds, so a second
  /// record for a device takes the next slot.
  private var working: [InsteonAddress: Eligible] = [:]

  /// The devices already refused as unable to take a write.
  private var unable: Set<InsteonAddress> = []

  init(change: SceneMembershipChange, modem: InsteonAddress, modemRecords: [BackupRecord], held: [InsteonAddress: BackupDevice]) {

    self.change = change
    self.modem = modem
    self.modemRecords = modemRecords
    self.held = held
    readLines = modemRecords.filter(\.isInUse).map { (record: BackupRecord) -> String in "modemRecord \(SceneMembershipPlanner.line(record))" }

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

  // MARK: What a scene holds

  /// The modem's controller records of the device in the scene: its half of a link.
  private func modemLinks(of address: InsteonAddress) -> [BackupRecord] {

    modemRecords.filter { (record: BackupRecord) -> Bool in
      record.isInUse && record.role == .controller && record.group == change.scene && record.address == address
    }

  }

  /// The device's responder records of the scene: its half of a link, one for each of its groups that answers.
  private func deviceLinks(in eligible: Eligible) -> [BackupRecord] {

    eligible.records.filter { (record: BackupRecord) -> Bool in
      record.isInUse && record.role == .responder && record.group == change.scene && record.address == modem
    }

  }

  // MARK: Eligibility

  /// Checks that the device's cached database was read whole and that its engine takes a remote
  /// write, and records the device's facts.
  private mutating func eligibility(of address: InsteonAddress, registered: RegisteredDevice?, needsIdentity: Bool = false) -> Eligible? {

    if let held = working[address] {

      return held

    }

    guard !unable.contains(address) else {

      return nil

    }

    let held: BackupDevice? = self.held[address]
    let engine: InsteonEngine? = (held?.engine).map(Self.engine) ?? registered?.info.engine
    var fact = SceneMembershipDevice(address: address, product: registered?.info.displayName, engine: engine, acceptsRemoteWrite: false)

    func refuse(_ code: SceneMembershipFinding.Code, _ detail: String? = nil) -> Eligible? {

      unable.insert(address)
      devices.append(fact)
      refusals.append(SceneMembershipFinding(code: code, device: address, detail: detail))

      return nil

    }

    // What the catalog says about the device comes first: without it the engine isn't judged.
    if needsIdentity {

      guard let registered else {

        return refuse(.notIdentified, "The service has no identity recorded for the device, so the catalog can't say what its record holds.")

      }

      guard registered.info.isInCatalog else {

        return refuse(.notInCatalog, "The catalog doesn't describe the identity the device reported.")

      }

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

    let eligible = Eligible(records: database.records, engine: engine ?? .i2cs)
    working[address] = eligible

    return eligible

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
  /// says so, or the catalog gives the record none, so the device has the one group. A record too short
  /// to hold the byte is for no group; ``isShort(_:at:)`` finds it first.
  private static func isRecord(_ record: BackupRecord, ofGroup group: UInt8, at position: Int?) -> Bool {

    guard let position else {

      return true

    }

    return record.data.count >= position && record.data[position - 1] == group

  }

  /// Whether a record is too short to hold the data byte at `position`.
  private static func isShort(_ record: BackupRecord, at position: Int?) -> Bool {

    guard let position else {

      return false

    }

    return record.data.count < position

  }

  // MARK: Adding

  mutating func add(_ addition: SceneMembershipChange.Addition, registered: RegisteredDevice?, modemLinkData: ModemLinkData?) {

    let address: InsteonAddress = addition.device

    guard let eligible = eligibility(of: address, registered: registered, needsIdentity: true), let registered else {

      return

    }

    func refuse(_ code: SceneMembershipFinding.Code, _ detail: String? = nil) {

      refusals.append(SceneMembershipFinding(code: code, device: address, detail: detail))

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

    let modemHalf: BackupRecord? = modemLinks(of: address).first
    let sceneRecords: [BackupRecord] = deviceLinks(in: eligible)
    if sceneRecords.contains(where: { (record: BackupRecord) -> Bool in Self.isShort(record, at: groupPosition) }) {

      refuse(.unexpectedDatabaseLayout, "A cached record of the device in the scene is too short to say which group it is for. Refresh the scenes to read it again.")

      return

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

      let modemData: [UInt8] = DeviceLinkingCoordinator.modemData(modemLinkData, isController: true, identity: registered.identity)

      steps.append(SceneMembershipStep(kind: .addModemRecord, endpoint: .modem, record: LinkRecord(isController: true, isInUse: true, group: group, address: address, data: modemData)))
      modemRecords.append(BackupRecord(state: .inUse, role: .controller, group: change.scene, address: address, data: modemData))
      addedHalf = true

      if let deviceHalf, deviceHalf.data != data {

        warnings.append(SceneMembershipFinding(code: .halfLinkCompleted, device: address, detail: "The device's record was in place with another on-level or ramp rate, and the modem's was missing. The modem's record is added; the device's is not rewritten until that has been tried on hardware."))

      } else if deviceHalf != nil {

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

    // The writes assume the records run from the highest address down and end with the end's record, so
    // a slot that isn't free or the end's is never written over.
    guard Self.hasExpectedLayout(records) else {

      refusals.append(SceneMembershipFinding(code: .unexpectedDatabaseLayout, device: address, detail: "The cached database isn't laid out as a write assumes: records from the highest address down, free slots above the end, and the end's record last. Refresh the scenes to read it again."))

      return false

    }

    if let free = records.first(where: { (held: BackupRecord) -> Bool in held.state == .free && held.memoryAddress != nil }), let slot = free.memoryAddress {

      var written: LinkRecord = record
      written.memoryAddress = slot
      steps.append(SceneMembershipStep(kind: .addDeviceRecord, endpoint: .device(address), record: written))
      let updated: [BackupRecord] = records.map { (held: BackupRecord) -> BackupRecord in
        held.memoryAddress == slot ? writtenRecord(data, at: slot) : held
      }
      working[address]?.records = updated

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
    // The end's slot holds the record after the write, and the slot below it is the end.
    let updated: [BackupRecord] = records.dropLast() + [
      writtenRecord(data, at: end),
      BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: newEnd)
    ]
    working[address]?.records = updated

    return true

  }

  /// Whether the records each have a slot, run strictly downward in address, and end with the one
  /// record that marks the end.
  private static func hasExpectedLayout(_ records: [BackupRecord]) -> Bool {

    let addresses: [UInt16] = records.compactMap(\.memoryAddress)

    guard addresses.count == records.count, zip(addresses, addresses.dropFirst()).allSatisfy({ (pair: (UInt16, UInt16)) -> Bool in pair.0 > pair.1 }) else {

      return false

    }

    return records.last?.state == .end && records.filter { (record: BackupRecord) -> Bool in record.state == .end }.count == 1

  }

  /// The cached record of a responder record the plan writes to the slot.
  private func writtenRecord(_ data: [UInt8], at slot: UInt16) -> BackupRecord {

    BackupRecord(state: .inUse, role: .responder, group: change.scene, address: modem, data: data, memoryAddress: slot)

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

  mutating func remove(_ address: InsteonAddress, groups: [UInt8]?, registered: RegisteredDevice?) {

    guard let eligible = eligibility(of: address, registered: registered) else {

      return

    }

    func refuse(_ code: SceneMembershipFinding.Code, _ detail: String) {

      refusals.append(SceneMembershipFinding(code: code, device: address, detail: detail))

    }

    let sceneRecords: [BackupRecord] = deviceLinks(in: eligible)
    var doomed: [BackupRecord] = sceneRecords

    if let groups {

      guard let registered else {

        refuse(.notIdentified, "The service has no identity recorded for the device, so the catalog can't say which of its records is for the group.")

        return

      }

      doomed = []

      for asked in groups {

        let description: DeviceDescription = registered.deviceDescription

        guard let named = description.profile?.groups.first(where: { (group: DeviceProfile.Group) -> Bool in group.number.rawValue == asked }) else {

          refuse(.unknownGroup, "The catalog gives the device no group \(asked).")

          return

        }

        guard let position = description.groupType(forGroup: named.number)?.linkData.responder.first(where: \.isPerGroup)?.position else {

          // A record with no byte for the device's own group is for its main group alone.
          guard named.number == description.mainGroup?.number else {

            refuse(.unknownGroup, "The catalog gives the device's record no byte for its own group, so only its main group is in a scene.")

            return

          }

          doomed += sceneRecords.filter { (record: BackupRecord) -> Bool in !doomed.contains(record) }

          continue

        }

        if sceneRecords.contains(where: { (record: BackupRecord) -> Bool in Self.isShort(record, at: position) }) {

          refuse(.unexpectedDatabaseLayout, "A cached record of the device in the scene is too short to say which group it is for. Refresh the scenes to read it again.")

          return

        }

        doomed += sceneRecords.filter { (record: BackupRecord) -> Bool in Self.isRecord(record, ofGroup: asked, at: position) }

      }

    }

    let modemHalves: [BackupRecord] = modemLinks(of: address)
    let staying: [BackupRecord] = sceneRecords.filter { (record: BackupRecord) -> Bool in !doomed.contains(record) }
    // The modem's record goes when no group of the device stays in the scene, and then first, so the
    // device keeps its record of the modem until its last write.
    let removedModem: [BackupRecord] = staying.isEmpty ? modemHalves : []

    guard doomed.allSatisfy({ (record: BackupRecord) -> Bool in record.memoryAddress != nil }) else {

      refuse(.unexpectedDatabaseLayout, "The cached database gives no slot for a record to clear. Refresh the scenes to read it again.")

      return

    }

    guard !removedModem.isEmpty || !doomed.isEmpty else {

      warnings.append(SceneMembershipFinding(code: .notAMember, device: address))

      return

    }

    for modemHalf in removedModem {

      steps.append(SceneMembershipStep(kind: .removeModemRecord, endpoint: .modem, record: LinkRecord(isController: true, isInUse: false, group: group, address: address, data: modemHalf.data)))

    }

    let otherLinks: Int = eligible.records.filter { (record: BackupRecord) -> Bool in
      record.isInUse && record.address == modem && !doomed.contains(record)
    }.count

    for (index, deviceHalf) in doomed.enumerated() {

      let isLast: Bool = index == doomed.count - 1
      let risks: [SceneMembershipStep.Risk] = isLast && eligible.engine == .i2cs && otherLinks == 0 ? [.rejectsModemOnceUnlinked] : []

      steps.append(SceneMembershipStep(kind: .removeDeviceRecord, endpoint: .device(address), record: LinkRecord(isController: false, isInUse: false, group: group, address: modem, data: deviceHalf.data, memoryAddress: deviceHalf.memoryAddress), risks: risks))

    }

  }

}
