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

  /// How many records were deleted from the modem.
  private(set) var modemDeletions = 0

  /// Whether the modem was asked for its own address.
  private(set) var wasAskedForItsAddress = false

  private var subscribers: [AsyncStream<ModemReply>.Continuation] = []

  private static let end = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  func setModemRecords(_ records: [AllLinkRecord]) {

    modemRecords = records

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
    default:
      break
    }

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    let device = message.destination

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
