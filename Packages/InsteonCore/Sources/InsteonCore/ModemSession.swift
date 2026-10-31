import Foundation
import InsteonHubClient
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// An open modem: a Hub's, reached over the local network with its user name and password, or
/// a PowerLinc Modem on a serial or USB port.
///
/// A session exists only while the closure it's opened with runs, and the modem closes when
/// the closure returns or throws. It asks the modem for what the modem knows and does itself,
/// such as its identity, a beep or a scene, and makes the ``DeviceNetwork`` that reaches the
/// devices through it:
///
/// ```swift
/// try await ModemSession.withHub(host: host, port: HubLocation.defaultPort, user: user, password: password) { session in
///   let info = try await session.info()
///   let network = session.network(catalog: catalog, snapshot: NetworkSnapshot(), hub: session.hub)
///
///   print(info.address, try await network.modemDatabase().count)
/// }
/// ```
///
/// The Hub's credentials go only into the Hub's own requests, which refuse redirects; they
/// aren't kept in the session, its ``hub``, or any error. Errors are described by
/// ``InsteonErrorDescription``, and ``HubFailure`` says when a Hub stopped answering.
public struct ModemSession: Sendable {

  /// The modem.
  let modem: Modem

  /// The Hub the modem is reached through, without its credentials, or `nil` for a modem on a
  /// serial or USB port.
  public let hub: HubLocation?

  init(modem: Modem, hub: HubLocation?) {

    self.modem = modem
    self.hub = hub

  }

  // MARK: - Opening

  /// Opens a Hub's modem, runs `body` with it, and closes it.
  ///
  /// The Hub's credentials go only to an IPv4 address in `10.0.0.0/8`, `172.16.0.0/12` or
  /// `192.168.0.0/16`. Any other host, such as a host name, an IPv6, loopback or link-local
  /// address, or a public address, is refused with ``HubAddressRefused`` before anything is
  /// sent. Requests go to the Hub directly, never through a proxy.
  ///
  /// - Parameters:
  ///   - host: The Hub's private IPv4 address, such as `192.168.1.20`.
  ///   - port: The Hub's port, such as ``HubLocation/defaultPort``.
  ///   - user: The Hub's user name.
  ///   - password: The Hub's password.
  ///   - body: The work to do with the modem.
  /// - Throws: ``HubAddressRefused`` for a host that isn't a private IPv4 address, the error
  ///   `body` throws, or the connection's, such as the Hub's `HubStoppedAnswering`, which
  ///   ``HubFailure`` reads.
  public static func withHub(
    host: String,
    port: Int,
    user: String,
    password: String,
    _ body: @Sendable (ModemSession) async throws -> Void
  ) async throws {

    // Checked before the Hub is made, so nothing is sent to a host that's refused.
    guard HubLocation(host: host, port: port).acceptsCredentials else {

      throw HubAddressRefused(host: host)

    }

    let endpoint = HubEndpoint(host: host, port: port)
    let hub = Hub(endpoint: endpoint, user: user, password: password)
    let location = HubLocation(host: endpoint.host, port: endpoint.port)

    try await Modem.withConnection(HubConnection(hub: hub)) { (modem: Modem) async throws -> Void in

      try await body(ModemSession(modem: modem, hub: location))

    }

  }

  #if os(macOS) || os(Linux)
  /// Opens a PowerLinc Modem on a serial or USB port, runs `body` with it, and closes it.
  ///
  /// - Parameters:
  ///   - path: The port's device path, such as `/dev/ttyUSB0`.
  ///   - body: The work to do with the modem.
  /// - Throws: The port's error if it can't be opened or configured, or the error `body`
  ///   throws.
  public static func withSerialPort(path: String, _ body: @Sendable (ModemSession) async throws -> Void) async throws {

    let port = try SerialPort(path: path)
    defer { port.close() }

    try await Modem.withConnection(port) { (modem: Modem) async throws -> Void in

      try await body(ModemSession(modem: modem, hub: nil))

    }

  }
  #endif

  // MARK: - The modem

  /// The modem's identity, from Get IM Info.
  ///
  /// - Returns: The modem's Insteon ID, category, subcategory and firmware version.
  /// - Throws: The modem's error, or `CancellationError` if the task is canceled.
  public func info() async throws -> ModemInfo {

    try await modem.modemInfo()

  }

  /// Takes the modem out of linking mode with Cancel ALL-Linking.
  ///
  /// - Throws: The modem's error, or `CancellationError` if the task is canceled.
  public func cancelLinking() async throws {

    try await modem.send(.cancelAllLinking)

  }

  /// Makes the modem beep, once or twice.
  ///
  /// - Parameter isDouble: Whether to beep twice.
  /// - Throws: The modem's error, which ``SendFailure`` reads as the modem rejecting the
  ///   command or not answering, as a modem without a beeper does, or `CancellationError`.
  public func beep(isDouble: Bool) async throws {

    try await modem.send(isDouble ? .doubleBeep : .beep)

  }

  /// A network that reaches devices through the modem.
  ///
  /// - Parameters:
  ///   - catalog: The catalog to describe devices with, or `nil` to describe them by their
  ///     identities alone.
  ///   - snapshot: What the network knew before, such as a snapshot a
  ///     ``NetworkSnapshotStore`` loaded.
  ///   - hub: The Hub to record in the network's snapshot, such as ``hub``, or `nil` to keep
  ///     the Hub the snapshot names.
  /// - Returns: The network.
  public func network(catalog: ProductCatalog?, snapshot: NetworkSnapshot, hub: HubLocation?) -> DeviceNetwork {

    DeviceNetwork(modem: modem, catalog: catalog?.catalog, snapshot: snapshot, hub: hub)

  }

  // MARK: - Raw passthroughs

  /// Writes a serial command's bytes to the modem as they're given, and collects everything
  /// the modem sends for a time.
  ///
  /// Listening starts before the command is written, so nothing the modem sends is missed.
  /// The time is waited out in full unless the modem closes first. Check the bytes with
  /// ``SerialCommandPolicy`` before writing them.
  ///
  /// - Parameters:
  ///   - bytes: The command's bytes, starting with `0x02`.
  ///   - duration: How long to collect what the modem sends.
  ///   - clock: The clock that times the wait. Defaults to a `ContinuousClock`.
  /// - Returns: What the modem sent, in order.
  /// - Throws: The modem's error if the command isn't accepted, or `CancellationError`.
  public func write(
    rawCommand bytes: [UInt8],
    collectingFor duration: Duration,
    clock: any Clock<Duration> = ContinuousClock()
  ) async throws -> [RawModemReply] {

    let replies: AsyncStream<ModemReply> = await modem.replies()

    try await modem.write(rawCommand: bytes)

    let received: [ModemReply] = await Self.collect(replies, within: duration, clock: clock)

    return received.map { (reply: ModemReply) -> RawModemReply in RawModemReply(reply) }

  }

  /// Sends a device a message as it's given, then collects the other messages the device
  /// sends for a time.
  ///
  /// Listening starts before the message, so nothing the device sends is missed. The
  /// device's acknowledgment is handed to `onAcknowledgment` as soon as it arrives, and isn't
  /// among the messages returned.
  ///
  /// - Parameters:
  ///   - message: The message.
  ///   - duration: How long to collect what the device sends after its acknowledgment.
  ///   - clock: The clock that times the wait. Defaults to a `ContinuousClock`.
  ///   - onAcknowledgment: Called with the device's acknowledgment.
  /// - Returns: The other messages from the device, in order.
  /// - Throws: The modem's error, which ``SendFailure`` reads as the device rejecting the
  ///   message or not answering, or `CancellationError`.
  public func send(
    _ message: DirectMessage,
    collectingFor duration: Duration,
    clock: any Clock<Duration> = ContinuousClock(),
    onAcknowledgment: (ReceivedFrame) -> Void
  ) async throws -> [ReceivedFrame] {

    let device: InsteonAddress = message.device
    let replies: AsyncStream<ModemReply> = await modem.replies()
    let acknowledgment: ReceivedMessage

    if let extended = message.extended {

      acknowledgment = try await modem.request(extended)

    } else {

      acknowledgment = try await modem.request(StandardMessage(to: device, command: message.command))

    }

    onAcknowledgment(ReceivedFrame(acknowledgment))

    let received: [ModemReply] = await Self.collect(replies, within: duration, clock: clock)
    var skippedAcknowledgment = false
    var frames: [ReceivedFrame] = []

    for reply in received {

      guard case let .messageReceived(incoming) = reply, incoming.sender == device else {

        continue

      }

      // The acknowledgment comes through the stream too.
      if !skippedAcknowledgment, incoming == acknowledgment {

        skippedAcknowledgment = true
        continue

      }

      frames.append(ReceivedFrame(incoming))

    }

    return frames

  }

  /// Everything that arrives within a time, in order. The time is waited out in full unless
  /// the modem closes first.
  static func collect(_ replies: AsyncStream<ModemReply>, within duration: Duration, clock: any Clock<Duration>) async -> [ModemReply] {

    let collector = Task { () -> [ModemReply] in

      var collected: [ModemReply] = []

      for await reply in replies {

        collected.append(reply)

        if Task.isCancelled {

          break

        }

      }

      return collected

    }

    try? await clock.sleep(for: duration)
    collector.cancel()

    return await collector.value

  }

}

extension HubLocation {

  /// The port a Hub listens on unless its owner changed it in the Hub's settings: 25105.
  public static let defaultPort: Int = HubEndpoint.defaultPort

}

/// A message to one device, as a raw passthrough sends it: its two command bytes, and for an
/// extended message, its user data.
///
/// ```swift
/// let message = DirectMessage(to: lamp, command1: 0x2E, command2: 0x00, data: [0x01], hasChecksum: true)
/// print(message.userData ?? [])   // D1 through D14, with the checksum in D14.
/// ```
public struct DirectMessage: Hashable, Sendable {

  /// The device the message is for.
  public let device: InsteonAddress

  /// The message's cmd1.
  public let command1: UInt8

  /// The message's cmd2.
  public let command2: UInt8

  /// The extended message, or `nil` for a standard one.
  let extended: ExtendedMessage?

  /// Creates a message.
  ///
  /// - Parameters:
  ///   - device: The device the message is for.
  ///   - command1: The message's cmd1.
  ///   - command2: The message's cmd2.
  ///   - data: D1 onward of an extended message, of which the first 14 are sent and any left
  ///     out are `0x00`, or `nil` for a standard message.
  ///   - hasChecksum: Whether an extended message carries a checksum in D14.
  public init(to device: InsteonAddress, command1: UInt8, command2: UInt8, data: [UInt8]?, hasChecksum: Bool) {

    self.device = device
    self.command1 = command1
    self.command2 = command2

    guard let data else {

      self.extended = nil

      return

    }

    let command = Command(command1: command1, command2: command2)
    var userData = UserData()

    for (offset, byte) in data.prefix(UserData.count).enumerated() {

      userData[offset + 1] = byte

    }

    if hasChecksum {

      self.extended = ExtendedMessage(to: device, command: command, userData: userData)

    } else {

      self.extended = ExtendedMessage(to: device, command: command, userData: userData, integrity: UnprotectedIntegrity())

    }

  }

  /// D1 through D14 as they're sent, with any checksum set, or `nil` for a standard message.
  public var userData: [UInt8]? {

    extended?.userData.bytes

  }

  /// The message's command bytes.
  var command: Command {

    Command(command1: command1, command2: command2)

  }

}

/// A message the modem received from a device, as a raw passthrough shows it.
public struct ReceivedFrame: Hashable, Sendable {

  /// The bytes the modem sent for the message, from its Start of Text.
  public let frame: [UInt8]

  /// What the message says, as ``DeviceMonitor`` reads it.
  public let summary: DeviceMessageSummary

  init(_ message: ReceivedMessage) {

    self.frame = message.modemFrame
    self.summary = DeviceMessageSummary(message)

  }

}

/// Something the modem sent, as a raw passthrough shows it.
public enum RawModemReply: Hashable, Sendable {

  /// The modem's echo of a serial command: its bytes, ending with the ACK or NAK, and the
  /// kind of reply, as ``DeviceMonitor/replyKind(_:)`` names it.
  case echo(bytes: [UInt8], kind: String)

  /// A message from a device.
  case message(ReceivedFrame)

  /// A NAK, `0x15`, the modem sent on its own.
  case negativeAcknowledgment

  /// Any other reply: its kind, and the reply as the package describes it.
  case other(kind: String, description: String)

  init(_ reply: ModemReply) {

    switch reply {
    case let .echo(echo):
      let acknowledgment: UInt8 = echo.isAccepted ? 0x06 : 0x15

      self = .echo(
        bytes: [SerialCommand.startOfText, echo.number.rawValue] + echo.parameters + [acknowledgment],
        kind: DeviceMonitor.replyKind(reply)
      )
    case let .messageReceived(message):
      self = .message(ReceivedFrame(message))
    case .negativeAcknowledgment:
      self = .negativeAcknowledgment
    default:
      self = .other(kind: DeviceMonitor.replyKind(reply), description: "\(reply)")
    }

  }

}
