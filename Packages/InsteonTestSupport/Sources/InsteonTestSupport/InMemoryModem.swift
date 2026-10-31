import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem that keeps its own and its devices' ALL-Link databases in memory.
///
/// Each device's database is linear: its records count down by 8 from `0x0FFF`, and an
/// address that was never written holds a record that marks the end of the database.
///
/// Each stream ``replies()`` returns stops being fed once its reader stops reading, and
/// finishes when the modem is released.
public actor InMemoryModem: LinkingModem {

  /// A write to a device's database.
  public struct Write: Hashable, Sendable {

    /// The device written to.
    public let device: InsteonAddress

    /// The record's address in the device's database.
    public let address: UInt16

    /// Creates a write.
    public init(device: InsteonAddress, address: UInt16) {

      self.device = device
      self.address = address

    }

  }

  /// The modem's own address.
  public let address = InsteonAddress(0x11, 0x22, 0x33)

  /// Each device's records, by address.
  public var databases: [InsteonAddress: [UInt16: AllLinkRecord]] = [:]

  /// The modem's own records, in the order it found or added them.
  public var modemRecords: [AllLinkRecord] = []

  /// Every write to a device's database, in order.
  public private(set) var writes: [Write] = []

  /// Devices that reject every request, as an i2CS device does before it's linked to the modem.
  public var unlinkedDevices: Set<InsteonAddress> = []

  /// Devices that acknowledge writes without storing them.
  public var forgetfulDevices: Set<InsteonAddress> = []

  /// The addresses of records in each device's database that arrive with a checksum that
  /// fails, as a record damaged on the way does.
  public var damagedRecords: [InsteonAddress: Set<UInt16>] = [:]

  /// Flags each device sets on its own in every record in use written to it.
  public var maintainedFlags: [InsteonAddress: AllLinkRecordFlags] = [:]

  /// Something the modem was asked to do in linking, in order.
  public enum LinkingStep: Hashable, Sendable {

    /// The modem entered linking or unlinking mode.
    case modem(AllLinkMode, AllLinkGroupNumber)

    /// The modem left linking mode.
    case cancel

    /// A device was sent a command, in a standard or extended message.
    case device(InsteonAddress, Command, isExtended: Bool)

  }

  /// The linking steps taken, in order.
  public private(set) var linkingSteps: [LinkingStep] = []

  /// An extended message sent to a device: its command and its user data, integrity bytes
  /// included.
  public struct ExtendedRequest: Hashable, Sendable {

    /// The device it was sent to.
    public let device: InsteonAddress

    /// Its cmd1 and cmd2.
    public let command: Command

    /// Its user data, D1 through D14.
    public let userData: UserData

    /// Creates a request.
    public init(device: InsteonAddress, command: Command, userData: UserData) {

      self.device = device
      self.command = command
      self.userData = userData

    }

  }

  /// Every extended message sent to a device, in order, whatever it does.
  public private(set) var extendedRequests: [ExtendedRequest] = []

  /// The engine each device reports. Devices not listed report i2.
  public var engines: [InsteonAddress: InsteonEngine] = [:]

  /// Engine versions devices report that ``InsteonEngine`` doesn't name, by device.
  public var unknownEngines: [InsteonAddress: UInt8] = [:]

  /// The SET Button Pressed broadcast each device sends in reply to an ID request. Devices not
  /// listed don't reply.
  public var identities: [InsteonAddress: SetButtonPressed] = [:]

  /// Devices that never complete a link.
  public var silentDevices: Set<InsteonAddress> = []

  /// Devices that acknowledge no standard message, so each one sent to them throws
  /// `ModemError.deviceTimedOut`.
  public var unansweringDevices: Set<InsteonAddress> = []

  /// Devices whose unlinks the modem carries out without reporting them.
  public var unreportedUnlinks: Set<InsteonAddress> = []

  /// The group the modem reports for each device's links, when it isn't the modem's group.
  public var reportedGroups: [InsteonAddress: AllLinkGroupNumber] = [:]

  /// Whether the modem keeps its own records in step with the links it reports: a controller
  /// or responder record for a link it makes, and none for a link it removes. Defaults to `false`, so
  /// the modem's records change only as a test sets them.
  public var recordsLinks: Bool = false

  /// Each device's level, from the Light On or Light Off it was last sent. Devices not listed
  /// are off.
  public private(set) var levels: [InsteonAddress: UInt8] = [:]

  /// The mode the modem is in, if it's linking.
  private var linkingMode: (mode: AllLinkMode, group: AllLinkGroupNumber)?

  /// The device waiting in linking or unlinking mode, if any.
  private var waitingDevice: (address: InsteonAddress, isUnlinking: Bool)?

  /// How many records were deleted from the modem.
  public private(set) var modemDeletions = 0

  /// Each device's ALL-Link database delta, which changes with every write to its database.
  private var deltas: [InsteonAddress: UInt8] = [:]

  /// How many times each device's whole database was read.
  public private(set) var databaseReads: [InsteonAddress: Int] = [:]

  /// How many times the modem's whole database was read.
  public private(set) var modemDatabaseReads = 0

  /// Whether the modem was asked for its own address.
  public private(set) var wasAskedForItsAddress = false

  /// The streams ``replies()`` returned that are still read, by the order they were made.
  private var subscribers: [Int: AsyncStream<ModemReply>.Continuation] = [:]

  private var nextSubscriber: Int = 0

  /// Creates a modem with no records, whose devices have empty databases.
  public init() {}

  deinit {

    for continuation in subscribers.values {

      continuation.finish()

    }

  }

  /// Sets the level a device reports in its acknowledgment of a status request, as if it had
  /// been turned on or off at the device.
  public func setLevel(_ level: UInt8, of device: InsteonAddress) {

    levels[device] = level

  }

  private static let end = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  /// Replaces the modem's own records.
  public func setModemRecords(_ records: [AllLinkRecord]) {

    modemRecords = records

  }

  /// Sets the engine a device reports.
  public func setEngine(_ engine: InsteonEngine, of device: InsteonAddress) {

    engines[device] = engine

  }

  /// Makes a device never complete a link.
  public func setSilent(_ device: InsteonAddress) {

    silentDevices.insert(device)

  }

  /// Makes a device acknowledge no standard message, or acknowledge them again.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - isUnanswering: Whether the device stops acknowledging. Defaults to `true`.
  public func setUnanswering(_ device: InsteonAddress, _ isUnanswering: Bool = true) {

    if isUnanswering {

      unansweringDevices.insert(device)

    } else {

      unansweringDevices.remove(device)

    }

  }

  /// Makes the modem carry out a device's unlinks without reporting them.
  public func setUnlinkUnreported(_ device: InsteonAddress) {

    unreportedUnlinks.insert(device)

  }

  /// Sets the group the modem reports for a device's links.
  public func setReportedGroup(_ group: AllLinkGroupNumber, of device: InsteonAddress) {

    reportedGroups[device] = group

  }

  /// Makes the modem keep its own records in step with the links it reports, or stop.
  ///
  /// - Parameter isRecording: Whether the modem adds and removes its records as it reports
  ///   links. Defaults to `true`.
  public func setRecordsLinks(_ isRecording: Bool = true) {

    recordsLinks = isRecording

  }

  /// Sets an engine version a device reports that `InsteonEngine` doesn't name.
  public func setUnknownEngine(_ version: UInt8, of device: InsteonAddress) {

    unknownEngines[device] = version

  }

  /// Sets the SET Button Pressed broadcast a device sends in reply to an ID request.
  public func setIdentity(_ identity: SetButtonPressed) {

    identities[identity.sender] = identity

  }

  /// A device broadcasts its identity, if it has one.
  public func broadcastIdentity(of device: InsteonAddress) {

    guard let identity = identities[device] else {

      return

    }

    let broadcast = ReceivedMessage(
      sender: device,
      destination: InsteonAddress(identity.category.rawValue, identity.subcategory.rawValue, identity.firmwareVersion?.rawValue ?? 0xFF),
      flags: MessageFlags(messageType: .broadcast),
      command: Command(command1: identity.role.rawValue, command2: 0x00)
    )

    for subscriber in subscribers.values {

      subscriber.yield(.messageReceived(broadcast))

    }

  }

  /// Someone presses a device's SET button: it enters linking mode, or unlinking mode.
  public func pressSetButton(of device: InsteonAddress, unlinking: Bool = false) {

    waitingDevice = (device, unlinking)
    completeLink()

  }

  /// Replaces a device's records, by address.
  public func setDatabase(_ records: [UInt16: AllLinkRecord], of device: InsteonAddress) {

    databases[device] = records

  }

  /// Makes a device reject every request, as an i2CS device does before it's linked to the modem.
  public func setUnlinked(_ device: InsteonAddress) {

    unlinkedDevices.insert(device)

  }

  /// Makes the record at an address in a device's database arrive with a checksum that fails,
  /// or arrive whole again.
  ///
  /// - Parameters:
  ///   - isDamaged: Whether the record arrives damaged.
  ///   - address: The record's address in the device's database.
  ///   - device: The device.
  public func setDamaged(_ isDamaged: Bool, record address: UInt16, of device: InsteonAddress) {

    if isDamaged {

      damagedRecords[device, default: []].insert(address)

    } else {

      _ = damagedRecords[device]?.remove(address)

    }

  }

  /// The record at an address in a device's database as it arrives, with its checksum.
  private func arrivingRecord(of device: InsteonAddress, at address: UInt16) -> AllLinkRecordResponse {

    AllLinkRecordResponse(
      sender: device,
      address: address,
      record: record(of: device, at: address),
      hasIntactChecksum: !(damagedRecords[device]?.contains(address) ?? false)
    )

  }

  /// Makes a device acknowledge writes without storing them.
  public func setForgetful(_ device: InsteonAddress) {

    forgetfulDevices.insert(device)

  }

  /// The device sets `flags` in every record in use written to it, as an i3 device may set its
  /// fast fail and smart hop bits.
  public func setMaintainedFlags(_ flags: AllLinkRecordFlags, of device: InsteonAddress) {

    maintainedFlags[device] = flags

  }

  /// Someone changes a device's database without the linker, such as by pressing its SET
  /// button, so its delta changes.
  public func changeDatabase(of device: InsteonAddress) {

    deltas[device, default: 0] &+= 1

  }

  /// The record at an address in a device's database, or the record that marks the end of the database.
  public func record(of device: InsteonAddress, at address: UInt16) -> AllLinkRecord {

    databases[device]?[address] ?? Self.end

  }

  // MARK: - LinkingModem

  /// Returns the modem's address, category, subcategory and firmware version, and records
  /// that it was asked.
  public func modemInfo() async throws -> ModemInfo {

    wasAskedForItsAddress = true

    return ModemInfo(address: address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)

  }

  /// Carries out a serial command: changes the modem's own records, or enters or leaves
  /// linking mode. Other commands are accepted and do nothing.
  public func send(_ command: SerialCommand) async throws {

    switch command {
    case let .manageAllLinkRecord(action, record):
      try manage(record, action: action)
    case let .startAllLinking(mode, group):
      linkingSteps.append(.modem(mode, group))
      linkingMode = (mode, group)
      completeLink()
    case .cancelAllLinking:
      linkingSteps.append(.cancel)
      linkingMode = nil
    default:
      break
    }

  }

  /// Answers a standard message as the device it's sent to would: a status request with the
  /// device's delta and level, Get Insteon Engine Version with its engine, ID Request with an
  /// acknowledgment and then its SET Button Pressed broadcast, Light On and Light Off by
  /// setting its level, and a linking command by entering linking mode.
  ///
  /// - Throws: `ModemError.deviceTimedOut` for a device that acknowledges nothing, and
  ///   `ModemError.deviceRejected` for a request an unlinked device rejects.
  public func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    let device = message.destination
    var command2 = message.command.command2

    guard !unansweringDevices.contains(device) else {

      throw ModemError.deviceTimedOut(device)

    }

    if message.command.command1 == 0x19 {

      guard !unlinkedDevices.contains(device) else {

        throw ModemError.deviceRejected(device, .notLinked)

      }

      // A status request's acknowledgment carries the database delta in cmd1 and the level
      // in cmd2.
      return ReceivedMessage(
        sender: device,
        destination: address,
        flags: MessageFlags(messageType: .directAcknowledgment),
        command: Command(command1: deltas[device, default: 0], command2: levels[device, default: 0x00])
      )

    }

    if message.command.command1 == 0x0D {

      linkingSteps.append(.device(device, message.command, isExtended: false))

      // An i2CS device rejects a modem it isn't linked to.
      guard !unlinkedDevices.contains(device) else {

        throw ModemError.deviceRejected(device, .notLinked)

      }

      command2 = unknownEngines[device] ?? (engines[device] ?? .i2).rawValue

    } else if message.command.command1 == 0x10 {

      guard !unlinkedDevices.contains(device) else {

        throw ModemError.deviceRejected(device, .notLinked)

      }

      // The device acknowledges, then broadcasts its identity.
      broadcastIdentity(of: device)

    } else if [0x11, 0x13].contains(message.command.command1) {

      linkingSteps.append(.device(device, message.command, isExtended: false))

      guard !unlinkedDevices.contains(device) else {

        throw ModemError.deviceRejected(device, .notLinked)

      }

      levels[device] = message.command.command1 == 0x11 ? message.command.command2 : 0x00

    } else {

      enterLinking(device, message.command, isExtended: false)

    }

    return ReceivedMessage(
      sender: device,
      destination: address,
      flags: MessageFlags(messageType: .directAcknowledgment),
      command: Command(command1: message.command.command1, command2: command2)
    )

  }

  /// Answers an extended message as the device it's sent to would: a linking command enters
  /// linking mode, and a write to its ALL-Link database stores the record, unless the device
  /// forgets writes.
  ///
  /// - Throws: `ModemError.deviceRejected` for a message an unlinked device rejects.
  public func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    let device = message.destination

    extendedRequests.append(ExtendedRequest(device: device, command: message.command, userData: message.userData))

    if [0x09, 0x0A].contains(message.command.command1) {

      enterLinking(device, message.command, isExtended: true)

      return ReceivedMessage(
        sender: device,
        destination: address,
        flags: MessageFlags(messageType: .directAcknowledgment),
        command: message.command
      )

    }

    guard !unlinkedDevices.contains(device) else {

      throw ModemError.deviceRejected(device, .notLinked)

    }

    let data = message.userData

    if message.command == ExtendedDirectCommand.readWriteAllLinkDatabase.command, data[2] == 0x02 {

      let recordAddress = UInt16(data[3]) << 8 | UInt16(data[4])

      writes.append(Write(device: device, address: recordAddress))

      if !forgetfulDevices.contains(device) {

        changeDatabase(of: device)
        databases[device, default: [:]][recordAddress] = AllLinkRecord(
          flags: AllLinkRecordFlags(rawValue: data[6]).union(data[6] & 0x80 != 0 ? maintainedFlags[device, default: []] : []),
          group: AllLinkGroupNumber(rawValue: data[7]),
          address: InsteonAddress(data[8], data[9], data[10]),
          data1: data[11],
          data2: data[12],
          data3: data[13]
        )

      }

    }

    return ReceivedMessage(
      sender: device,
      destination: address,
      flags: MessageFlags(messageType: .directAcknowledgment),
      command: message.command
    )

  }

  /// Returns the record at an address in a device's database, where `0x0000` asks for the
  /// first record, at `0x0FFF`.
  ///
  /// - Throws: `ModemError.deviceRejected` for an unlinked device.
  public func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    guard !unlinkedDevices.contains(device) else {

      throw ModemError.deviceRejected(device, .notLinked)

    }

    let recordAddress: UInt16 = address == 0x0000 ? 0x0FFF : address

    return arrivingRecord(of: device, at: recordAddress)

  }

  /// Returns the modem's own records for a group and device.
  public func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    modemRecords.filter { $0.group == group && $0.address == device }

  }

  /// Returns the modem's own records, and counts the read.
  public func allLinkRecords() async throws -> [AllLinkRecord] {

    modemDatabaseReads += 1

    return modemRecords

  }

  /// Returns a device's records from `0x0FFF` down, ending with the record that marks the
  /// end of its database, and counts the read.
  ///
  /// - Throws: `ModemError.deviceRejected` for an unlinked device.
  public func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    guard !unlinkedDevices.contains(device) else {

      throw ModemError.deviceRejected(device, .notLinked)

    }

    databaseReads[device, default: 0] += 1

    var responses: [AllLinkRecordResponse] = []
    var recordAddress: UInt16 = 0x0FFF

    while true {

      let response: AllLinkRecordResponse = arrivingRecord(of: device, at: recordAddress)

      responses.append(response)

      guard !response.isEndOfDatabase, recordAddress > 8 else {

        return responses

      }

      recordAddress -= 8

    }

  }

  /// Returns a stream of the broadcasts and link reports the modem sends after this call.
  ///
  /// The stream finishes when the modem is released, and stops being fed once its reader
  /// stops reading.
  public func replies() -> AsyncStream<ModemReply> {

    let (stream, continuation) = AsyncStream<ModemReply>.makeStream()
    let id: Int = nextSubscriber

    nextSubscriber += 1
    subscribers[id] = continuation

    continuation.onTermination = { [weak self] (_: AsyncStream<ModemReply>.Continuation.Termination) -> Void in

      guard let self else {

        return

      }

      Task {

        await self.removeSubscriber(id)

      }

    }

    return stream

  }

  /// Stops feeding a stream whose reader stopped reading.
  private func removeSubscriber(_ id: Int) {

    subscribers[id] = nil

  }

  // MARK: - Linking

  private func enterLinking(_ device: InsteonAddress, _ command: Command, isExtended: Bool) {

    linkingSteps.append(.device(device, command, isExtended: isExtended))

    switch command.command1 {
    case 0x09, 0x0A:
      waitingDevice = (device, command.command1 == 0x0A)
      completeLink()
    case 0x08:
      waitingDevice = nil
    default:
      break
    }

  }

  /// Reports a link once the modem and a device are both in linking mode.
  private func completeLink() {

    guard let linking = linkingMode, let waiting = waitingDevice else {

      return

    }

    if waiting.isUnlinking, unreportedUnlinks.contains(waiting.address) {

      modemRecords.removeAll { $0.address == waiting.address && $0.group == linking.group && !$0.flags.contains(.controller) }
      linkingMode = nil
      waitingDevice = nil

      return

    }

    guard !silentDevices.contains(waiting.address) else {

      return

    }

    let linkCode = linking.mode == .delete || waiting.isUnlinking ? 0xFF : linking.mode.rawValue
    let link = AllLinkingCompleted(
      linkCode: linkCode,
      group: reportedGroups[waiting.address] ?? linking.group,
      address: waiting.address,
      category: nil,
      subcategory: nil,
      firmwareVersion: nil
    )

    linkingMode = nil
    waitingDevice = nil

    // A device that joins the modem's group memorizes its level as the link's data.
    if linkCode == AllLinkMode.controller.rawValue {

      memorizeResponderLink(of: waiting.address, group: link.group)

    }

    if recordsLinks {

      recordLink(link, modemMode: linking.mode)

    }

    for subscriber in subscribers.values {

      subscriber.yield(.allLinkingCompleted(link))

    }

  }

  /// Adds the modem's record for a link it reports, or removes the record of a link it removed:
  /// its controller record when it was in unlinking mode, and its responder record when it
  /// joined a device that was.
  private func recordLink(_ link: AllLinkingCompleted, modemMode: AllLinkMode) {

    switch link.mode {
    case .controller?:
      addModemRecord(AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: link.group, address: link.address))
    case .responder?:
      addModemRecord(AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: link.group, address: link.address))
    case .delete?:
      let removesController: Bool = modemMode == .delete

      modemRecords.removeAll { (record: AllLinkRecord) -> Bool in

        record.address == link.address && record.group == link.group && record.flags.contains(.controller) == removesController

      }
    default:
      break
    }

  }

  /// Adds a record to the modem's own database, unless one for the same device, group and role
  /// is there.
  private func addModemRecord(_ record: AllLinkRecord) {

    let isController: Bool = record.flags.contains(.controller)
    let isThere: Bool = modemRecords.contains { (stored: AllLinkRecord) -> Bool in

      stored.address == record.address && stored.group == record.group && stored.flags.contains(.controller) == isController

    }

    if !isThere {

      modemRecords.append(record)

    }

  }

  /// Adds a responder record of the modem to a device's database, after its last record, with
  /// the device's level as Data 1.
  private func memorizeResponderLink(of device: InsteonAddress, group: AllLinkGroupNumber) {

    let count: Int = databases[device]?.count ?? 0
    let recordAddress: UInt16 = 0x0FFF - UInt16(count) * 8

    databases[device, default: [:]][recordAddress] = AllLinkRecord(
      flags: AllLinkRecordFlags(rawValue: 0xA2),
      group: group,
      address: address,
      data1: levels[device, default: 0x00],
      data2: 0x1C,
      data3: 0x01
    )

  }

  // MARK: - The modem's database

  private func manage(_ record: AllLinkRecord, action: AllLinkRecordAction) throws {

    switch action {
    case .modifyFirstControllerOrAdd, .modifyFirstResponderOrAdd:
      let isController = action == .modifyFirstControllerOrAdd

      var stored = record

      if isController {

        stored.flags.insert(.controller)

      } else {

        stored.flags.remove(.controller)

      }

      if let index = modemRecords.firstIndex(where: {

        $0.group == record.group && $0.address == record.address && $0.flags.contains(.controller) == isController

      }) {

        modemRecords[index] = stored

      } else {

        modemRecords.append(stored)

      }
    case .deleteFirst:
      // The modem matches a record to delete by its group and address, and NAKs when there's none.
      guard let index = modemRecords.firstIndex(where: { $0.group == record.group && $0.address == record.address }) else {

        throw ModemError.rejected(.manageAllLinkRecord)

      }

      modemRecords.remove(at: index)
      modemDeletions += 1
    default:
      break
    }

  }

}
