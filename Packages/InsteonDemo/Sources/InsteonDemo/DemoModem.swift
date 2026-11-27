import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem that holds a few made-up devices in memory.
///
/// Each device answers Light On, Light Off and Light Status Request, and keeps the level it was
/// given. The modem's ALL-Link database holds a controller record for each scene member, and
/// each member's database holds the matching responder record.
actor DemoModem: LinkingModem {

  private let address: InsteonAddress
  private var levels: [InsteonAddress: UInt8]
  private let modemRecords: [AllLinkRecord]
  private let memberRecords: [InsteonAddress: [AllLinkRecord]]

  /// Creates a modem for these devices and scenes.
  ///
  /// - Parameters:
  ///   - address: The modem's address.
  ///   - devices: The devices, all off.
  ///   - scenes: Each scene's group and its members.
  init(
    address: InsteonAddress = DemoNetwork.modem,
    devices: [InsteonAddress] = DemoNetwork.devices.map(\.address),
    scenes: [DemoNetwork.Scene] = DemoNetwork.scenes
  ) {

    self.address = address
    self.levels = Dictionary(uniqueKeysWithValues: devices.map { ($0, 0x00) })

    var controllers: [AllLinkRecord] = []
    var responders: [InsteonAddress: [AllLinkRecord]] = [:]

    for scene in scenes {

      for member in scene.members {

        controllers.append(AllLinkRecord(flags: [.inUse, .controller], group: scene.group, address: member, data1: 0x00))
        responders[member, default: []].append(AllLinkRecord(flags: [.inUse], group: scene.group, address: address, data1: 0xFF, data2: 0x1F, data3: 0x01))

      }

    }

    self.modemRecords = controllers
    self.memberRecords = responders

  }

  func send(_ command: SerialCommand) async throws {}

  func modemInfo() async throws -> ModemInfo {

    ModemInfo(address: address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    let device: InsteonAddress = message.destination

    guard levels[device] != nil else {

      throw ModemError.deviceTimedOut(device)

    }

    let sent: Command = message.command

    switch sent.command1 {

    case 0x11, 0x12:
      levels[device] = sent.command2

    case 0x13, 0x14:
      levels[device] = 0x00

    case 0x19:
      // A status request's acknowledgment carries the database delta in cmd1 and the level in cmd2.
      return acknowledgment(from: device, Command(command1: 0x00, command2: levels[device] ?? 0x00))

    default:
      break

    }

    return acknowledgment(from: device, sent)

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    guard levels[message.destination] != nil else {

      throw ModemError.deviceTimedOut(message.destination)

    }

    return acknowledgment(from: message.destination, message.command)

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    guard levels[device] != nil else {

      throw ModemError.deviceTimedOut(device)

    }

    var responses: [AllLinkRecordResponse] = []
    var recordAddress: UInt16 = 0x0FFF

    for record in memberRecords[device, default: []] {

      responses.append(AllLinkRecordResponse(sender: device, address: recordAddress, record: record, hasIntactChecksum: true))
      recordAddress -= 8

    }

    responses.append(AllLinkRecordResponse(sender: device, address: recordAddress, record: Self.end, hasIntactChecksum: true))

    return responses

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    let responses: [AllLinkRecordResponse] = try await readAllLinkDatabase(of: device, timeout: timeout)
    let wanted: UInt16 = address == 0x0000 ? 0x0FFF : address

    return responses.first { $0.address == wanted } ?? AllLinkRecordResponse(sender: device, address: wanted, record: Self.end, hasIntactChecksum: true)

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    modemRecords.filter { $0.group == group && $0.address == device }

  }

  func allLinkRecords() async throws -> [AllLinkRecord] {

    modemRecords

  }

  func sendAllLinkCommand(group: AllLinkGroupNumber, command: Command, wait: AllLinkCleanupWait) async throws -> AllLinkCleanupReport {

    var members: [InsteonAddress] = []

    for record in modemRecords where record.flags.contains(.controller) && record.group == group && !members.contains(record.address) {

      members.append(record.address)

    }

    guard !members.isEmpty else {

      throw ModemError.rejected(.sendAllLinkCommand)

    }

    for member in members {

      switch command.command1 {

      case 0x11, 0x12:
        levels[member] = command.command2

      case 0x13, 0x14:
        levels[member] = 0x00

      default:
        break

      }

    }

    return AllLinkCleanupReport(acknowledged: members, unacknowledged: [], isComplete: true)

  }

  func replies() async -> AsyncStream<ModemReply> {

    AsyncStream<ModemReply> { _ in }

  }

  /// The record that marks the end of a database.
  private static let end = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  private func acknowledgment(from device: InsteonAddress, _ command: Command) -> ReceivedMessage {

    ReceivedMessage(sender: device, destination: address, flags: MessageFlags(messageType: .directAcknowledgment), command: command)

  }

}
