import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem with one device that keeps operating flags and extended settings values, as
/// ``ControlExample/dimmerCommands`` describes them: Get Operating Flags reports the flags, Set
/// Operating Flags `0x0A` and `0x0B` set and clear bit `0x02`, an extended Get replies with the
/// values, and an extended Set with selector `0x05` or `0x06` writes D3 to the value at D7 or D8.
actor SettingsModem: LinkingModem {

  /// The modem's own address.
  let address = InsteonAddress(0x11, 0x22, 0x33)

  /// The device.
  let device: InsteonAddress

  /// The device's operating flags.
  private(set) var flags: UInt8

  /// The device's values, by the user data byte an extended Get's reply holds them in.
  private(set) var values: [Int: UInt8]

  /// Whether the device acknowledges writes without changing anything.
  private var ignoresWrites: Bool = false

  /// Every standard command sent, in order.
  private(set) var standardCommands: [Command] = []

  /// Every extended message sent, in order.
  private(set) var extendedMessages: [ExtendedMessage] = []

  private var subscribers: [Int: AsyncStream<ModemReply>.Continuation] = [:]

  private var nextSubscriber: Int = 0

  /// Creates a modem with a device.
  ///
  /// - Parameters:
  ///   - device: The device's address.
  ///   - flags: The device's operating flags.
  ///   - values: The device's values, by the user data byte that holds them.
  init(device: InsteonAddress, flags: UInt8, values: [Int: UInt8]) {

    self.device = device
    self.flags = flags
    self.values = values

  }

  deinit {

    for continuation in subscribers.values {

      continuation.finish()

    }

  }

  /// Makes the device acknowledge writes without changing anything.
  func ignoreWrites() {

    ignoresWrites = true

  }

  // MARK: - LinkingModem

  func send(_ command: SerialCommand) async throws {}

  func modemInfo() async throws -> ModemInfo {

    ModemInfo(address: address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    standardCommands.append(message.command)

    var command2: UInt8 = message.command.command2

    switch message.command.command1 {
    case 0x1F:
      command2 = flags
    case 0x0D:
      command2 = InsteonEngine.i2.rawValue
    case 0x20:
      apply(message.command.command2)
    default:
      break
    }

    return acknowledgment(Command(command1: message.command.command1, command2: command2))

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    extendedMessages.append(message)

    let data: UserData = message.userData

    if message.command.command1 == 0x2E {

      if data[2] == 0x00 {

        var reply = UserData()
        reply[1] = data[1]
        reply[2] = 0x01

        for (position, value) in values {

          reply[position] = value

        }

        let received = ReceivedMessage(
          sender: device,
          destination: address,
          flags: MessageFlags(messageType: .direct, isExtended: true),
          command: Command(command1: 0x2E, command2: 0x00),
          userData: reply
        )

        for subscriber in subscribers.values {

          subscriber.yield(.messageReceived(received))

        }

      } else if !ignoresWrites, let position = Self.positions[data[2]] {

        values[position] = data[3]

      }

    } else if message.command.command1 == 0x20 {

      apply(message.command.command2)

    }

    return acknowledgment(message.command)

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    throw ModemError.deviceTimedOut(device)

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    throw ModemError.deviceTimedOut(device)

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    []

  }

  func allLinkRecords() async throws -> [AllLinkRecord] {

    []

  }

  func replies() -> AsyncStream<ModemReply> {

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

  // MARK: - Helpers

  /// The value each extended Set selector writes, by the byte an extended Get's reply holds
  /// it in.
  private static let positions: [UInt8: Int] = [0x05: 7, 0x06: 8]

  private func removeSubscriber(_ id: Int) {

    subscribers[id] = nil

  }

  /// Sets or clears bit `0x02` for Set Operating Flags `0x0A` or `0x0B`.
  private func apply(_ command2: UInt8) {

    guard !ignoresWrites else {

      return

    }

    switch command2 {
    case 0x0A:
      flags |= 0x02
    case 0x0B:
      flags &= ~0x02
    default:
      break
    }

  }

  private func acknowledgment(_ command: Command) -> ReceivedMessage {

    ReceivedMessage(sender: device, destination: address, flags: MessageFlags(messageType: .directAcknowledgment), command: command)

  }

}
