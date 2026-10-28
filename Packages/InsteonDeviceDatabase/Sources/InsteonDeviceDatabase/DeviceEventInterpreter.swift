import InsteonProtocol

/// Reads the messages a modem receives as ``DeviceEvent``s, using each device's profile.
///
/// The interpreter learns a device's profile when the device reports its identity, such as
/// when its SET button is held to link it, or from ``DeviceEventInterpreter/remember(_:for:)``
/// for devices an app already knows. From then on, the device's group commands carry what
/// its profile says they mean, so a product is supported by its profile alone.
///
/// Group commands pass through a ``GroupCommandFilter`` first, so each command a device sends
/// is reported once however many times it's repeated or cleaned up.
///
/// ```swift
/// var interpreter = DeviceEventInterpreter<ContinuousClock.Instant>(database: try .bundled())
///
/// for await reply in await modem.replies() {
///   guard case let .messageReceived(message) = reply else { continue }
///
///   for event in interpreter.events(from: message, at: .now) {
///     if case let .groupCommand(command, event: "wet"?) = event {
///       print("\(command.controller) detected water")
///     }
///   }
/// }
/// ```
///
/// The interpreter keeps no clock of its own: give it the time each message arrived, from any
/// clock, so tests can use one they control.
public struct DeviceEventInterpreter<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration, Instant: Sendable {

  /// The database profiles are found in.
  public let database: DeviceDatabase

  private var filter: GroupCommandFilter<Instant>

  private var profiles: [InsteonAddress: DeviceProfile] = [:]

  /// Creates an interpreter that knows no devices yet.
  ///
  /// - Parameters:
  ///   - database: The database to find profiles in.
  ///   - filter: The filter group commands pass through. Defaults to one with its default
  ///     windows.
  public init(database: DeviceDatabase, filter: GroupCommandFilter<Instant> = GroupCommandFilter()) {

    self.database = database
    self.filter = filter

  }

  /// The profile known for a device.
  ///
  /// - Parameter device: The device's address.
  /// - Returns: The profile, or `nil` if the device hasn't reported a known identity and
  ///   hasn't been remembered.
  public func profile(of device: InsteonAddress) -> DeviceProfile? {

    profiles[device]

  }

  /// Records a device's profile, such as one an app saved from an earlier session.
  ///
  /// - Parameters:
  ///   - profile: The profile, or `nil` to forget the device.
  ///   - device: The device's address.
  public mutating func remember(_ profile: DeviceProfile?, for device: InsteonAddress) {

    profiles[device] = profile

  }

  /// The events a message carries.
  ///
  /// - Parameters:
  ///   - message: A message the modem received.
  ///   - instant: When the message arrived.
  /// - Returns: The events, in the order they happened, or none if the message isn't one a
  ///   device sends to report something, or repeats a group command already reported.
  public mutating func events(from message: ReceivedMessage, at instant: Instant) -> [DeviceEvent] {

    if let pressed = SetButtonPressed(message) {

      return [identify(pressed.sender, pressed.category, pressed.subcategory, pressed.firmwareVersion)]

    }

    if let heartbeat = Heartbeat(message) {

      return [identify(heartbeat.sender, heartbeat.category, heartbeat.subcategory, heartbeat.firmwareVersion), .heartbeat(heartbeat.sender)]

    }

    if let changed = DeviceStatusChanged(message) {

      return [identify(changed.sender, changed.category, changed.subcategory, changed.firmwareVersion), .statusChanged(changed.sender)]

    }

    guard let command = filter.command(from: message, at: instant) else {

      return []

    }

    guard let profile = profiles[command.controller] else {

      return [.groupCommand(command, event: nil)]

    }

    for case let .heartbeat(group, _) in profile.capabilities where group == command.group {

      return [.heartbeat(command.controller)]

    }

    return [.groupCommand(command, event: profile.event(group: command.group, command1: command.command1))]

  }

  /// Records the profile matching a device's reported identity, and reports it.
  private mutating func identify(_ device: InsteonAddress, _ category: DeviceCategory, _ subcategory: DeviceSubcategory, _ firmwareVersion: FirmwareVersion?) -> DeviceEvent {

    let profile = database.profile(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)
    profiles[device] = profile

    return .identified(device, profile: profile)

  }

}
