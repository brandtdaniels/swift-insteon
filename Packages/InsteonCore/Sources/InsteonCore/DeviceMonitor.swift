import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// Watches what a network's modem hears, and reads it as events: which device sent what, to
/// which group, and what the Insteon device catalog says it means.
///
/// ``DeviceNetwork/monitor`` hands one out. Each stream ``changes(includingRaw:)`` returns
/// reads the modem's replies as its reader asks for events, in the reader's task, so nothing
/// runs when nobody reads, and canceling the reader's task, or the modem's replies finishing,
/// ends the stream:
///
/// ```swift
/// let changes = await network.monitor.changes()
///
/// for await event in changes {
///   if case let .groupCommand(command) = event, command.event == "wet" {
///     print("\(command.device) detected water")
///   }
/// }
/// ```
///
/// A device's group commands carry what its profile says they mean once the device is known:
/// from the identities the network's registry holds when the stream starts, and from any
/// identity a device reports while it runs, such as when its SET button is pressed. The
/// monitor records those identities in the registry, and that each device that sent a message
/// answered at the network's current time, so the network's ``DeviceNetwork/snapshot()``
/// keeps them.
public struct DeviceMonitor: Sendable {

  /// The network whose modem is watched.
  public let network: DeviceNetwork

  /// Creates a monitor of a network.
  init(network: DeviceNetwork) {

    self.network = network

  }

  /// The events the modem hears from now on, until the reader's task is canceled or the
  /// modem's replies finish.
  ///
  /// The modem's replies are subscribed to before this returns, so nothing the modem hears
  /// after is missed. Read the stream from one task.
  ///
  /// A repeat of a group command, or its cleanup, is reported once, as the catalog's
  /// `DeviceEventInterpreter` does, and so is a repeat of a broadcast that reports an
  /// identity. A message that's neither, such as an acknowledgment, is reported as
  /// ``DeviceMonitorEvent/message(_:)``.
  ///
  /// - Parameter includingRaw: Whether to add the bytes of each message the modem received,
  ///   before its events, and the kind of each reply that isn't otherwise reported, for a
  ///   front end that shows them. With it, a broadcast that reports nothing is reported as
  ///   ``DeviceMonitorEvent/message(_:)`` too. Defaults to `false`.
  /// - Returns: The events.
  public func changes(includingRaw: Bool = false) async -> AsyncStream<DeviceMonitorEvent> {

    let replies: AsyncStream<ModemReply> = await network.modem.replies()
    let catalog: DeviceCatalog = await network.registry.catalog ?? DeviceCatalog(profiles: [])
    let known: [InsteonAddress: ReportedIdentity] = await network.registry.snapshot.identities

    return Self.stream(replies: replies, catalog: catalog, known: known, network: network, clock: network.clock, includingRaw: includingRaw)

  }

  /// The stream of events, timed by the clock the network was created with, so a test can
  /// give one it controls.
  private static func stream<C: Clock>(
    replies: AsyncStream<ModemReply>,
    catalog: DeviceCatalog,
    known: [InsteonAddress: ReportedIdentity],
    network: DeviceNetwork,
    clock: C,
    includingRaw: Bool
  ) -> AsyncStream<DeviceMonitorEvent> where C.Duration == Duration {

    var interpreter = DeviceMonitorInterpreter<C.Instant>(catalog: catalog, includingRaw: includingRaw)

    for (device, identity) in known {

      interpreter.remember(identity, for: device)

    }

    let feed = MonitorFeed(replies: replies, interpreter: interpreter, network: network, clock: clock)

    return AsyncStream<DeviceMonitorEvent>(unfolding: { () async -> DeviceMonitorEvent? in

      await feed.next()

    })

  }

  /// The kind of a reply the modem sent, as a front end names a reply that isn't a message
  /// from a device, such as `"ALL-Link record"` or `"echo of Get IM Info"`.
  ///
  /// - Parameter reply: The reply.
  /// - Returns: The kind.
  public static func replyKind(_ reply: ModemReply) -> String {

    switch reply {
    case .messageReceived: "Insteon message"
    case .x10Received: "X10 received"
    case .allLinkingCompleted: "ALL-Linking Completed"
    case .buttonEvent: "button event"
    case .userReset: "user reset"
    case .allLinkCleanupFailed: "ALL-Link cleanup failure"
    case .allLinkRecord: "ALL-Link record"
    case .allLinkCleanupStatus: "ALL-Link cleanup status"
    case .databaseRecord: "database record"
    case .diagnosticRecord: "diagnostic record"
    case .deviceRecordFound: "device record"
    case .radioStatus: "radio status"
    case .modemInfo: "Get IM Info reply"
    case .modemConfiguration: "configuration"
    case let .echo(echo): "echo of \(echo.number.name)\(echo.isAccepted ? "" : ", NAK")"
    case .negativeAcknowledgment: "NAK"
    }

  }

}

/// Something a ``DeviceMonitor`` heard.
public enum DeviceMonitorEvent: Hashable, Sendable {

  /// A device reported its identity, in a heartbeat broadcast or when its status changed.
  /// The associated values are the device and its product's name and model, or `nil` if the
  /// catalog doesn't have its identity. An identity reported by a SET Button Pressed broadcast
  /// is ``setButtonPressed(_:)`` instead.
  case identified(InsteonAddress, productName: String?)

  /// A device's SET button was pressed, so it reported its identity and how it links.
  case setButtonPressed(DeviceSetButtonPress)

  /// A device sent a command to one of its groups.
  case groupCommand(DeviceGroupCommand)

  /// A device sent its periodic heartbeat to the heartbeat group its profile gives. The
  /// associated values are the device and the group.
  case heartbeat(InsteonAddress, group: Int)

  /// A device sent a heartbeat broadcast. The associated values are the device and its
  /// battery level.
  case heartbeatBroadcast(InsteonAddress, batteryLevel: UInt8)

  /// A device's status changed; ask it with ``Device/status(group:)``.
  case statusChanged(InsteonAddress)

  /// A message that reports none of the other events, such as an acknowledgment, as it is.
  case message(DeviceMessageSummary)

  /// The modem reported something on its own.
  case modem(ModemNotice)

  /// The bytes the modem sent for a message, before its events, from a stream that includes
  /// them, such as `02 50 1A 2B 3C 11 22 33 8F 11 FF`.
  case rawMessage([UInt8])

  /// A reply the modem sent that isn't a message from a device and isn't otherwise reported,
  /// from a stream that includes it, by its kind, as ``DeviceMonitor/replyKind(_:)`` names it.
  case rawReply(kind: String)

}

/// A command a device sent to one of its groups, with what its profile says it means.
public struct DeviceGroupCommand: Hashable, Sendable {

  /// The device that sent the command.
  public var device: InsteonAddress

  /// The group the command was sent to.
  public var group: Int

  /// The command's cmd1, such as `0x11`.
  public var command1: UInt8

  /// The command's name in the Insteon Developer's Guide, such as `"Light On"`, or `nil` if it
  /// has none.
  public var commandName: String?

  /// What the device's profile says the command means, such as `"wet"` or `"motion"`, or
  /// `nil` if the device isn't known or its profile doesn't say. The same name means the same
  /// thing across products.
  public var event: String?

  /// Whether the command turns the group on, as an ALL-Link Recall or an Alias High does, or
  /// off, as an Alias Low does, or `nil` if it's neither.
  public var isOn: Bool?

  /// The product's name and model, as the catalog gives them, or `nil` if the device isn't
  /// known.
  public var productName: String?

  /// Creates a group command.
  ///
  /// - Parameters:
  ///   - device: The device that sent the command.
  ///   - group: The group the command was sent to.
  ///   - command1: The command's cmd1.
  ///   - commandName: The command's name.
  ///   - event: What the device's profile says the command means.
  ///   - isOn: Whether the command turns the group on or off.
  ///   - productName: The product's name and model.
  public init(device: InsteonAddress, group: Int, command1: UInt8, commandName: String?, event: String?, isOn: Bool?, productName: String?) {

    self.device = device
    self.group = group
    self.command1 = command1
    self.commandName = commandName
    self.event = event
    self.isOn = isOn
    self.productName = productName

  }

  /// The group command a device sent, with what its profile says it means.
  init(_ command: GroupCommand, event: DeviceEventName?, productName: String?) {

    let isOn: Bool?

    switch command.allLinkCommand?.buttonState {
    case .high?:
      isOn = true
    case .low?:
      isOn = false
    case nil:
      isOn = nil
    }

    self.init(
      device: command.controller,
      group: Int(command.group.rawValue),
      command1: command.command1,
      commandName: StandardDirectCommand.name(command1: command.command1),
      event: event?.rawValue,
      isOn: isOn,
      productName: productName
    )

  }

}

/// A device's SET Button Pressed broadcast: the identity it reported and how it links.
public struct DeviceSetButtonPress: Hashable, Sendable {

  /// The device whose SET button was pressed.
  public var device: InsteonAddress

  /// The identity the device reported.
  public var identity: ReportedIdentity

  /// The broadcast's cmd1, which says how the device links: `0x01` as a responder, `0x02` as
  /// a controller.
  public var command1: UInt8

  /// How the device links, in words: `"responder"` or `"controller"`.
  public var role: String

  /// The product's name and model, as the catalog gives them for the identity, or `nil` if
  /// the catalog doesn't have it.
  public var productName: String?

  /// Creates a SET button press from the broadcast.
  ///
  /// - Parameters:
  ///   - pressed: The broadcast.
  ///   - productName: The product's name and model, if the catalog has the identity.
  public init(_ pressed: SetButtonPressed, productName: String?) {

    self.device = pressed.sender
    self.identity = ReportedIdentity(pressed)
    self.command1 = pressed.role.rawValue
    self.role = pressed.role.name
    self.productName = productName

  }

}

/// A message from a device, as a front end shows it: who sent it to whom, its type and its
/// command.
public struct DeviceMessageSummary: Hashable, Sendable {

  /// The device that sent the message.
  public var sender: InsteonAddress

  /// The address the message was sent to, which for a broadcast holds other things, such as
  /// a group or an identity.
  public var destination: InsteonAddress

  /// The message type's name, such as `"ACK"` or `"ALL-Link broadcast"`.
  public var type: String

  /// Whether the message is extended.
  public var isExtended: Bool

  /// The message's cmd1.
  public var command1: UInt8

  /// The message's cmd2.
  public var command2: UInt8

  /// The name of cmd1 as a direct command in the Insteon Developer's Guide, such as
  /// `"Light On"`, or `nil` if it has none.
  public var commandName: String?

  /// Creates a summary of a message.
  ///
  /// - Parameter message: A message the modem received.
  public init(_ message: ReceivedMessage) {

    self.sender = message.sender
    self.destination = message.destination
    self.type = message.flags.messageType.name
    self.isExtended = message.userData != nil
    self.command1 = message.command.command1
    self.command2 = message.command.command2
    self.commandName = StandardDirectCommand.name(command1: message.command.command1)

  }

}

/// Something the modem reported on its own, rather than in reply to a command.
public enum ModemNotice: Hashable, Sendable {

  /// ALL-Linking completed with a device. The associated values are the device, the group
  /// and the modem's role in the link, such as `"controller"`, or `nil` if it reported none.
  case allLinkingCompleted(InsteonAddress, group: Int, modemRole: String?)

  /// A button on the modem was pressed, held or released, as the modem described it.
  case buttonEvent(String)

  /// The modem was reset to factory defaults with its SET button.
  case userReset

  /// A device didn't acknowledge an ALL-Link cleanup. The associated values are the device
  /// and the group.
  case allLinkCleanupFailed(InsteonAddress, group: Int)

  /// The modem received an X10 code, as it described it.
  case x10Received(String)

  /// What the modem reported on its own, or `nil` for a reply to the host's commands.
  init?(_ reply: ModemReply) {

    switch reply {
    case let .allLinkingCompleted(link):
      self = .allLinkingCompleted(link.address, group: Int(link.group.rawValue), modemRole: link.mode?.name)
    case let .buttonEvent(event):
      self = .buttonEvent(String(describing: event))
    case .userReset:
      self = .userReset
    case let .allLinkCleanupFailed(group, address):
      self = .allLinkCleanupFailed(address, group: Int(group.rawValue))
    case let .x10Received(code):
      self = .x10Received(String(describing: code))
    default:
      return nil
    }

  }

}

// MARK: - Interpreting

/// Reads the modem's replies as ``DeviceMonitorEvent``s, with the catalog's
/// `DeviceEventInterpreter`, and says what the network should record.
struct DeviceMonitorInterpreter<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration, Instant: Sendable {

  /// What a reply carries: its events, the device that sent it, and the identity it reported
  /// the first time it reported it.
  struct Interpretation: Hashable, Sendable {

    var events: [DeviceMonitorEvent]

    var sender: InsteonAddress?

    var identity: ReportedIdentity?

  }

  private var interpreter: DeviceEventInterpreter<Instant>

  private let includesRaw: Bool

  /// Creates an interpreter that knows no devices yet.
  init(catalog: DeviceCatalog, includingRaw: Bool) {

    self.interpreter = DeviceEventInterpreter<Instant>(catalog: catalog)
    self.includesRaw = includingRaw

  }

  /// Records a device's identity, such as one the network's registry holds.
  mutating func remember(_ identity: ReportedIdentity, for device: InsteonAddress) {

    interpreter.remember(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion, for: device)

  }

  /// What a reply carries, in the order a front end shows it: a message's bytes, when they're
  /// included; a SET button press; the message's other events; and the message as it is when
  /// it reports none of them.
  mutating func interpret(_ reply: ModemReply, at instant: Instant) -> Interpretation {

    guard case let .messageReceived(message) = reply else {

      if let notice = ModemNotice(reply) {

        return Interpretation(events: [.modem(notice)])

      }

      return Interpretation(events: includesRaw ? [.rawReply(kind: DeviceMonitor.replyKind(reply))] : [])

    }

    var result: [DeviceMonitorEvent] = includesRaw ? [.rawMessage(message.modemFrame)] : []
    var events: [DeviceEvent] = interpreter.events(from: message, at: instant)
    let identified: DeviceEvent? = events.first(where: Self.isIdentified)
    let pressed: SetButtonPressed? = SetButtonPressed(message)

    // A SET Button Pressed broadcast says how the device links, along with its identity. The
    // interpreter reports the identity only the first time, so a repeat isn't reported again.
    if let pressed {

      if case let .identified(_, profile)? = identified {

        result.append(.setButtonPressed(DeviceSetButtonPress(pressed, productName: profile?.displayName)))

      }

      events.removeAll(where: Self.isIdentified)

    }

    for event in events {

      result.append(monitorEvent(for: event))

    }

    // Broadcasts and cleanups are the interpreter's to report, and it leaves out repeats;
    // other messages, such as acknowledgments, are reported as they are, and every message
    // is when its bytes are.
    switch message.flags.messageType {
    case .broadcast, .allLinkBroadcast, .allLinkCleanup:
      if includesRaw, events.isEmpty, pressed == nil {

        result.append(.message(DeviceMessageSummary(message)))

      }
    case .direct, .directAcknowledgment, .directNegativeAcknowledgment, .allLinkCleanupAcknowledgment, .allLinkCleanupNegativeAcknowledgment:
      if events.isEmpty {

        result.append(.message(DeviceMessageSummary(message)))

      }
    }

    return Interpretation(events: result, sender: message.sender, identity: identified == nil ? nil : Self.identity(in: message))

  }

  /// The monitor's event for one of the catalog's.
  private func monitorEvent(for event: DeviceEvent) -> DeviceMonitorEvent {

    switch event {
    case let .identified(device, profile):
      .identified(device, productName: profile?.displayName)
    case let .groupCommand(command, name):
      .groupCommand(DeviceGroupCommand(command, event: name, productName: interpreter.profile(of: command.controller)?.displayName))
    case let .heartbeat(command):
      .heartbeat(command.controller, group: Int(command.group.rawValue))
    case let .heartbeatBroadcast(heartbeat):
      .heartbeatBroadcast(heartbeat.sender, batteryLevel: heartbeat.batteryLevel)
    case let .statusChanged(device):
      .statusChanged(device)
    }

  }

  /// Whether an event reports an identity.
  private static func isIdentified(_ event: DeviceEvent) -> Bool {

    if case .identified = event {

      return true

    }

    return false

  }

  /// The identity a broadcast reports, if it's one that reports one.
  private static func identity(in message: ReceivedMessage) -> ReportedIdentity? {

    if let pressed = SetButtonPressed(message) {

      return ReportedIdentity(pressed)

    }

    if let heartbeat = Heartbeat(message) {

      return ReportedIdentity(heartbeat)

    }

    if let changed = DeviceStatusChanged(message) {

      return ReportedIdentity(changed)

    }

    return nil

  }

}

extension DeviceMonitorInterpreter.Interpretation {

  /// An interpretation with events and nothing to record.
  init(events: [DeviceMonitorEvent]) {

    self.init(events: events, sender: nil, identity: nil)

  }

}

/// Reads the modem's replies for one stream, as its reader asks for events.
///
/// The stream calls ``next()`` once at a time, from its reader's task, so the iterator and the
/// interpreter are only ever used by one task at a time.
final class MonitorFeed<C: Clock>: @unchecked Sendable where C.Duration == Duration {

  private var replies: AsyncStream<ModemReply>.Iterator

  private var interpreter: DeviceMonitorInterpreter<C.Instant>

  private var pending: [DeviceMonitorEvent] = []

  private let network: DeviceNetwork

  private let clock: C

  init(replies: AsyncStream<ModemReply>, interpreter: DeviceMonitorInterpreter<C.Instant>, network: DeviceNetwork, clock: C) {

    self.replies = replies.makeAsyncIterator()
    self.interpreter = interpreter
    self.network = network
    self.clock = clock

  }

  /// The next event, or `nil` once the modem's replies finish or the reader's task is
  /// canceled.
  func next() async -> DeviceMonitorEvent? {

    while pending.isEmpty {

      guard let reply: ModemReply = await replies.next() else {

        return nil

      }

      let interpretation = interpreter.interpret(reply, at: clock.now)

      if let sender = interpretation.sender {

        await network.recordHeard(from: sender, identity: interpretation.identity)

      }

      pending = interpretation.events

    }

    return pending.removeFirst()

  }

}
