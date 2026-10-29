import InsteonProtocol

/// Reads the messages a modem receives as ``DeviceEvent``s, using each device's profile.
///
/// The interpreter learns a device's profile when the device reports an identity the catalog
/// knows, such as when its SET button is held to link it, or from
/// ``DeviceEventInterpreter/remember(category:subcategory:firmwareVersion:for:)`` for devices
/// an app already knows. From then on, the device's group commands carry what its profile says
/// they mean, so a product is supported by its profile alone. An identity the catalog doesn't
/// know leaves the device's profile as it was.
///
/// The interpreter keeps each device's identity, so setting
/// ``DeviceEventInterpreter/catalog`` to a newer catalog finds the device's profile in it. A
/// device remembered by its profile alone, with ``DeviceEventInterpreter/remember(_:for:)``,
/// keeps that profile when the catalog changes, even if the newer catalog describes the product
/// differently, so an app that saves devices should save their identities instead.
///
/// Group commands pass through a `GroupCommandFilter` first, so each command a device sends
/// is reported once however many times it's repeated or cleaned up. A broadcast that reports
/// an identity, which sensors also send twice, is reported once within the filter's
/// `duplicateWindow`.
///
/// ```swift
/// var interpreter = DeviceEventInterpreter<ContinuousClock.Instant>(catalog: try .bundled())
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

  /// What a device reported about itself.
  private struct Identity: Hashable, Sendable {

    let category: DeviceCategory

    let subcategory: DeviceSubcategory

    let firmwareVersion: FirmwareVersion?

  }

  /// An identity broadcast, for recognizing its repeat.
  private struct Broadcast: Hashable, Sendable {

    let sender: InsteonAddress

    let command: Command

  }

  /// The catalog profiles are found in. Setting it finds each device's profile again from the
  /// identity it last reported or was remembered with, so a newer catalog takes effect without
  /// losing what the interpreter has heard. A device the newer catalog doesn't know, or one
  /// remembered by its profile alone, keeps the profile it had.
  public var catalog: DeviceCatalog {

    didSet {

      for (device, identity) in identities {

        if let profile = catalog.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion) {

          profiles[device] = profile

        }

      }

    }

  }

  private var filter: GroupCommandFilter<Instant>

  private var profiles: [InsteonAddress: DeviceProfile] = [:]

  private var identities: [InsteonAddress: Identity] = [:]

  private var recentBroadcasts: [Broadcast: Instant] = [:]

  /// Creates an interpreter that knows no devices yet.
  ///
  /// - Parameters:
  ///   - catalog: The catalog to find profiles in.
  ///   - filter: The filter group commands pass through. Defaults to one with its default
  ///     windows.
  public init(catalog: DeviceCatalog, filter: GroupCommandFilter<Instant> = GroupCommandFilter()) {

    self.catalog = catalog
    self.filter = filter

  }

  /// The profile known for a device.
  ///
  /// - Parameter device: The device's address.
  /// - Returns: The profile, or `nil` if the device hasn't reported an identity the catalog
  ///   knows and hasn't been remembered.
  public func profile(of device: InsteonAddress) -> DeviceProfile? {

    profiles[device]

  }

  /// Records a device's profile, such as one an app saved from an earlier session.
  ///
  /// The interpreter keeps the profile as given: setting ``catalog`` doesn't replace it unless
  /// the device has reported an identity or been remembered with one. To have a newer catalog's
  /// profile take its place, use ``remember(category:subcategory:firmwareVersion:for:)``.
  ///
  /// - Parameters:
  ///   - profile: The profile, or `nil` to forget the device.
  ///   - device: The device's address.
  public mutating func remember(_ profile: DeviceProfile?, for device: InsteonAddress) {

    profiles[device] = profile

    if profile == nil {

      identities[device] = nil

    }

  }

  /// Records the identity a device reported, such as one an app saved from an earlier session,
  /// and finds its profile in the catalog.
  ///
  /// The interpreter keeps the identity, so setting ``catalog`` finds the device's profile again
  /// in the newer catalog. An identity the catalog doesn't know leaves the device's profile as it
  /// was, as when the device reports one itself.
  ///
  /// ```swift
  /// interpreter.remember(category: 0x10, subcategory: 0x08, firmwareVersion: 0x41, for: sensor)
  /// ```
  ///
  /// - Parameters:
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmwareVersion: The firmware version the device reported, or `nil` if it didn't
  ///     report one.
  ///   - device: The device's address.
  public mutating func remember(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?, for device: InsteonAddress) {

    let identity = Identity(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion)

    _ = identify(device, identity)

  }

  /// The events a message carries.
  ///
  /// - Parameters:
  ///   - message: A message the modem received.
  ///   - instant: When the message arrived.
  /// - Returns: The events, in the order they happened, or none if the message isn't one a
  ///   device sends to report something, or repeats one already reported.
  public mutating func events(from message: ReceivedMessage, at instant: Instant) -> [DeviceEvent] {

    if let pressed = SetButtonPressed(message) {

      guard isNew(message, at: instant) else { return [] }

      return [identify(pressed.sender, Identity(category: pressed.category, subcategory: pressed.subcategory, firmwareVersion: pressed.firmwareVersion))]

    }

    if let heartbeat = Heartbeat(message) {

      guard isNew(message, at: instant) else { return [] }

      let identity = Identity(category: heartbeat.category, subcategory: heartbeat.subcategory, firmwareVersion: heartbeat.firmwareVersion)

      return [identify(heartbeat.sender, identity), .heartbeatBroadcast(heartbeat)]

    }

    if let changed = DeviceStatusChanged(message) {

      guard isNew(message, at: instant) else { return [] }

      let identity = Identity(category: changed.category, subcategory: changed.subcategory, firmwareVersion: changed.firmwareVersion)

      return [identify(changed.sender, identity), .statusChanged(changed.sender)]

    }

    guard let command = filter.command(from: message, at: instant) else {

      return []

    }

    guard let profile = profiles[command.controller] else {

      return [.groupCommand(command, event: nil)]

    }

    // A named event wins over the heartbeat group, so a profile can name what a heartbeat's
    // command means.
    if let event = profile.event(group: command.group, command1: command.command1) {

      return [.groupCommand(command, event: event)]

    }

    if profile.heartbeatGroup == command.group {

      return [.heartbeat(command)]

    }

    return [.groupCommand(command, event: nil)]

  }

  /// Records the profile matching a device's reported identity, if the catalog has one, and
  /// reports it.
  private mutating func identify(_ device: InsteonAddress, _ identity: Identity) -> DeviceEvent {

    identities[device] = identity

    let profile = catalog.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)

    if let profile {

      profiles[device] = profile

    }

    return .identified(device, profile: profile)

  }

  /// Whether an identity broadcast isn't a repeat of one heard within the duplicate window.
  private mutating func isNew(_ message: ReceivedMessage, at instant: Instant) -> Bool {

    let window = filter.duplicateWindow
    recentBroadcasts = recentBroadcasts.filter { max(.zero, $0.value.duration(to: instant)) < window }

    let broadcast = Broadcast(sender: message.sender, command: message.command)

    guard recentBroadcasts[broadcast] == nil else {

      return false

    }

    recentBroadcasts[broadcast] = instant

    return true

  }

}
