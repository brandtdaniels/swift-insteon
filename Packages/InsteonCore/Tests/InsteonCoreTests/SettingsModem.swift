import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem with one device that keeps operating flags and extended settings values, as
/// ``ControlExample/dimmerCommands`` describes them: Get Operating Flags reports the flags, Set
/// Operating Flags `0x0A` and `0x0B` set and clear bit `0x02`, an extended Get replies with the
/// values, and an extended Set with selector `0x05`, `0x06` or `0x07` writes D3 to the value at
/// D7, D8 or D9.
/// Get Insteon Engine Version reports i2 unless told otherwise, and an extended Get for a
/// button whose values are set apart replies with that button's values. A write can also set
/// flag bits, as a device whose settings depend on each other does.
actor SettingsModem: LinkingModem {

  /// The modem's own address.
  let address = InsteonAddress(0x11, 0x22, 0x33)

  /// The device.
  let device: InsteonAddress

  /// The device's operating flags.
  private(set) var flags: UInt8

  /// The device's values, by the user data byte an extended Get's reply holds them in.
  private(set) var values: [Int: UInt8]

  /// The values of buttons whose values differ from the device's, by button.
  private(set) var buttonValues: [UInt8: [Int: UInt8]] = [:]

  /// Whether the device acknowledges writes without changing anything.
  private var ignoresWrites: Bool = false

  /// The flag bits an extended Set sets when it writes a value other than zero, by its selector.
  private var flagSideEffects: [UInt8: UInt8] = [:]

  /// The positions of the values that go up by one with every extended Get, as a value the
  /// device measures changes on its own.
  private var changingPositions: Set<Int> = []

  /// The engine the device reports to Get Insteon Engine Version.
  private var engine: InsteonEngine = .i2

  /// Whether the device rejects Get Insteon Engine Version.
  private var rejectsEngineRequests: Bool = false

  /// Every standard command sent, in order.
  private(set) var standardCommands: [Command] = []

  /// Every extended message sent, in order.
  private(set) var extendedMessages: [ExtendedMessage] = []

  /// Every message sent, in order, as its bytes: a standard message's cmd1 and cmd2, such as
  /// `"1F 00"`, and an extended message's cmd1, cmd2, D1, D2 and D3, such as
  /// `"2E 00 01 05 1C"`.
  private(set) var sent: [String] = []

  /// What runs before each message is carried out, given the message as ``sent`` writes it,
  /// which can throw to fail the message before it's carried out or logged.
  private var beforeSending: (@Sendable (String) throws -> Void)?

  /// The values an extended Set with a selector writes as well, by selector: the user data
  /// byte, the value, and the button whose values it writes, or `nil` for the button written.
  private var valueSideEffects: [UInt8: [(position: Int, value: UInt8, button: UInt8?)]] = [:]

  /// Every extended message sent but the extended Gets that read the values, in order.
  var extendedWrites: [ExtendedMessage] {

    extendedMessages.filter { (message: ExtendedMessage) -> Bool in message.command.command1 != 0x2E || message.userData[2] != 0x00 }

  }

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

  /// Sets the engine the device reports.
  func setEngine(_ engine: InsteonEngine) {

    self.engine = engine

  }

  /// Makes the device reject Get Insteon Engine Version, as an i2CS device does when it isn't
  /// linked to the modem.
  func rejectEngineRequests() {

    rejectsEngineRequests = true

  }

  /// Makes an extended Set with a selector set flag bits as well when it writes a value other
  /// than zero.
  ///
  /// - Parameters:
  ///   - bits: The flag bits it sets.
  ///   - selector: The extended Set's selector, in D2.
  func setFlagBits(_ bits: UInt8, whenWritingANonZeroValueWith selector: UInt8) {

    flagSideEffects[selector] = bits

  }

  /// Makes values go up by one with every extended Get, as a value the device measures
  /// changes on its own.
  ///
  /// - Parameter positions: The user data bytes that hold them.
  func changeValuesOnTheirOwn(at positions: Set<Int>) {

    changingPositions = positions

  }

  /// Runs `hook` before each message, given the message as ``sent`` writes it; a message the
  /// hook throws for fails with its error and isn't carried out or logged.
  func setBeforeSending(_ hook: (@Sendable (String) throws -> Void)?) {

    beforeSending = hook

  }

  /// Makes an extended Set with a selector write another value as well.
  ///
  /// - Parameters:
  ///   - selector: The extended Set's selector, in D2.
  ///   - value: The other value it writes.
  ///   - position: The user data byte that holds the other value.
  ///   - button: The button whose value it writes, or `nil` for the button written.
  func setValueSideEffect(ofSelector selector: UInt8, writes value: UInt8, at position: Int, ofButton button: UInt8? = nil) {

    valueSideEffects[selector, default: []].append((position, value, button))

  }

  /// Sets the values one button reports, by the user data byte that holds them.
  func setValues(_ values: [Int: UInt8], ofButton button: UInt8) {

    buttonValues[button] = values

  }

  // MARK: - LinkingModem

  func send(_ command: SerialCommand) async throws {}

  func modemInfo() async throws -> ModemInfo {

    ModemInfo(address: address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    let bytes: String = Self.hex([message.command.command1, message.command.command2])

    try beforeSending?(bytes)

    standardCommands.append(message.command)
    sent.append(bytes)

    var command2: UInt8 = message.command.command2

    switch message.command.command1 {
    case 0x1F:
      command2 = flags
    case 0x0D:
      if rejectsEngineRequests {

        throw ModemError.deviceRejected(device, .notLinked)

      }

      command2 = engine.rawValue
    case 0x20:
      apply(message.command.command2)
    default:
      break
    }

    return acknowledgment(Command(command1: message.command.command1, command2: command2))

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    let data: UserData = message.userData
    let bytes: String = Self.hex([message.command.command1, message.command.command2, data[1], data[2], data[3]])

    try beforeSending?(bytes)

    extendedMessages.append(message)
    sent.append(bytes)

    if message.command.command1 == 0x2E {

      if data[2] == 0x00 {

        var reply = UserData()
        reply[1] = data[1]
        reply[2] = 0x01

        for position in changingPositions {

          values[position, default: 0x00] &+= 1

        }

        for (position, value) in buttonValues[data[1]] ?? values {

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

        if buttonValues[data[1]] != nil {

          buttonValues[data[1]]?[position] = data[3]

        } else {

          values[position] = data[3]

        }

        for effect in valueSideEffects[data[2]] ?? [] {

          setValue(effect.value, at: effect.position, ofButton: effect.button ?? data[1])

        }

        if data[3] != 0x00, let bits = flagSideEffects[data[2]] {

          flags |= bits

        }

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
  private static let positions: [UInt8: Int] = [0x05: 7, 0x06: 8, 0x07: 9]

  /// Bytes as space-separated pairs.
  private static func hex(_ bytes: [UInt8]) -> String {

    bytes.map { (byte: UInt8) -> String in (byte < 0x10 ? "0" : "") + String(byte, radix: 16, uppercase: true) }.joined(separator: " ")

  }

  /// Writes a value of a button, or of the device when the button's values aren't set apart.
  private func setValue(_ value: UInt8, at position: Int, ofButton button: UInt8) {

    if buttonValues[button] != nil {

      buttonValues[button]?[position] = value

    } else {

      values[position] = value

    }

  }

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
