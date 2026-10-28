import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem that keeps its own and its devices' ALL-Link databases in memory.
///
/// Each device's database is linear: its records count down by 8 from `0x0FFF`, and an
/// address that was never written holds a record that marks the end of the database.
actor InMemoryModem: LinkingModem {

  /// A write to a device's database.
  struct Write: Hashable {

    let device: InsteonAddress

    let address: UInt16

  }

  let address = InsteonAddress(0x11, 0x22, 0x33)

  /// Each device's records, by address.
  var databases: [InsteonAddress: [UInt16: AllLinkRecord]] = [:]

  /// The modem's own records, in the order it found or added them.
  var modemRecords: [AllLinkRecord] = []

  /// Every write to a device's database, in order.
  private(set) var writes: [Write] = []

  /// Devices that reject every request, as an i2cs device does before it's linked to the modem.
  var unlinkedDevices: Set<InsteonAddress> = []

  /// Devices that acknowledge writes without storing them.
  var forgetfulDevices: Set<InsteonAddress> = []

  /// Something the modem was asked to do in linking, in order.
  enum LinkingStep: Hashable {

    /// The modem entered linking or unlinking mode.
    case modem(AllLinkMode, AllLinkGroupNumber)

    /// The modem left linking mode.
    case cancel

    /// A device was sent a command, in a standard or extended message.
    case device(InsteonAddress, Command, isExtended: Bool)

  }

  /// The linking steps taken, in order.
  private(set) var linkingSteps: [LinkingStep] = []

  /// The engine each device reports. Devices not listed report i2.
  var engines: [InsteonAddress: InsteonEngine] = [:]

  /// Devices that never complete a link.
  var silentDevices: Set<InsteonAddress> = []

  /// The mode the modem is in, if it's linking.
  private var linkingMode: (mode: AllLinkMode, group: AllLinkGroupNumber)?

  /// The device waiting in linking or unlinking mode, if any.
  private var waitingDevice: (address: InsteonAddress, isUnlinking: Bool)?

  /// How many records were deleted from the modem.
  private(set) var modemDeletions = 0

  /// Whether the modem was asked for its own address.
  private(set) var wasAskedForItsAddress = false

  private var subscribers: [AsyncStream<ModemReply>.Continuation] = []

  private static let end = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  func setModemRecords(_ records: [AllLinkRecord]) {

    modemRecords = records

  }

  func setEngine(_ engine: InsteonEngine, of device: InsteonAddress) {

    engines[device] = engine

  }

  func setSilent(_ device: InsteonAddress) {

    silentDevices.insert(device)

  }

  /// Someone presses a device's SET button: it enters linking mode, or unlinking mode.
  func pressSetButton(of device: InsteonAddress, unlinking: Bool = false) {

    waitingDevice = (device, unlinking)
    completeLink()

  }

  func setDatabase(_ records: [UInt16: AllLinkRecord], of device: InsteonAddress) {

    databases[device] = records

  }

  func setUnlinked(_ device: InsteonAddress) {

    unlinkedDevices.insert(device)

  }

  func setForgetful(_ device: InsteonAddress) {

    forgetfulDevices.insert(device)

  }

  func record(of device: InsteonAddress, at address: UInt16) -> AllLinkRecord {

    databases[device]?[address] ?? Self.end

  }

  // MARK: - LinkingModem

  func send(_ command: SerialCommand) async throws {

    switch command {
    case .getModemInfo:
      wasAskedForItsAddress = true

      let info = ModemInfo(address: address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)

      for subscriber in subscribers {

        subscriber.yield(.modemInfo(info))

      }
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

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    let device = message.destination
    var command2 = message.command.command2

    if message.command.command1 == 0x0D {

      // An i2cs device rejects a modem it isn't linked to.
      guard !unlinkedDevices.contains(device) else {

        throw ModemError.deviceRejected(device, .notLinked)

      }

      command2 = (engines[device] ?? .i2).rawValue

    } else {

      enterLinking(device, message.command, isExtended: false)

    }

    return ReceivedMessage(
      sender: device,
      destination: address,
      flags: MessageFlags(messageType: .directAcknowledgement),
      command: Command(command1: message.command.command1, command2: command2)
    )

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    let device = message.destination

    if [0x09, 0x0A].contains(message.command.command1) {

      enterLinking(device, message.command, isExtended: true)

      return ReceivedMessage(
        sender: device,
        destination: address,
        flags: MessageFlags(messageType: .directAcknowledgement),
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

        databases[device, default: [:]][recordAddress] = AllLinkRecord(
          flags: AllLinkRecordFlags(rawValue: data[6]),
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
      flags: MessageFlags(messageType: .directAcknowledgement),
      command: message.command
    )

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    guard !unlinkedDevices.contains(device) else {

      throw ModemError.deviceRejected(device, .notLinked)

    }

    let recordAddress: UInt16 = address == 0x0000 ? 0x0FFF : address

    return AllLinkRecordResponse(sender: device, address: recordAddress, record: record(of: device, at: recordAddress))

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    modemRecords.filter { $0.group == group && $0.address == device }

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    guard !unlinkedDevices.contains(device) else {

      throw ModemError.deviceRejected(device, .notLinked)

    }

    var responses: [AllLinkRecordResponse] = []
    var recordAddress: UInt16 = 0x0FFF

    while true {

      let response = AllLinkRecordResponse(sender: device, address: recordAddress, record: record(of: device, at: recordAddress))

      responses.append(response)

      guard !response.isEndOfDatabase, recordAddress > 8 else {

        return responses

      }

      recordAddress -= 8

    }

  }

  func replies() -> AsyncStream<ModemReply> {

    let (stream, continuation) = AsyncStream<ModemReply>.makeStream()

    subscribers.append(continuation)

    return stream

  }

  // MARK: - Linking

  private func enterLinking(_ device: InsteonAddress, _ command: Command, isExtended: Bool) {

    linkingSteps.append(.device(device, command, isExtended: isExtended))

    if [0x09, 0x0A].contains(command.command1) {

      waitingDevice = (device, command.command1 == 0x0A)
      completeLink()

    }

  }

  /// Reports a link once the modem and a device are both in linking mode.
  private func completeLink() {

    guard let linking = linkingMode, let waiting = waitingDevice, !silentDevices.contains(waiting.address) else {

      return

    }

    let linkCode = linking.mode == .delete || waiting.isUnlinking ? 0xFF : linking.mode.rawValue
    let link = AllLinkingCompleted(
      linkCode: linkCode,
      group: linking.group,
      address: waiting.address,
      category: nil,
      subcategory: nil,
      firmwareVersion: nil
    )

    linkingMode = nil
    waitingDevice = nil

    for subscriber in subscribers {

      subscriber.yield(.allLinkingCompleted(link))

    }

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
