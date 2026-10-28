/// Finds battery-powered devices that have gone quiet, such as a leak sensor whose battery
/// died or that was moved out of range.
///
/// Sensors send a heartbeat periodically, so a sensor that hasn't been heard from in much longer
/// than that has likely stopped working. The interval is about 23.8 hours for the leak, open/close
/// and motion sensors, with the first heartbeat as late as 23.8 hours after the batteries go in. A
/// device is silent once nothing has been heard from it for longer than
/// ``HeartbeatMonitor/allowance``.
///
/// Any message counts, not only a heartbeat: the sheet notes that a sensor restarts its
/// heartbeat interval when its button is pressed, so a sensor that's in use may send no
/// heartbeat for longer than the interval.
///
/// The monitor keeps no clock of its own: give it the time each message arrived and the time
/// to check, from any clock, so tests can use one they control. It keeps nothing across
/// launches either: to carry a device's time over, save how long ago it was last heard from,
/// ``HeartbeatMonitor/lastHeard(from:)`` measured against the wall clock, and watch it again
/// since that long before now.
///
/// ```swift
/// var monitor = HeartbeatMonitor<ContinuousClock.Instant>()
/// monitor.watch(leakSensor, since: .now)
///
/// // For each message the modem receives:
/// monitor.heard(from: message.sender, at: .now)
///
/// // Now and then:
/// for device in monitor.silentDevices(at: .now) {
///   print("No word from \(device)")
/// }
/// ```
public struct HeartbeatMonitor<Instant: InstantProtocol>: Sendable where Instant.Duration == Duration, Instant: Sendable {

  /// How long a device can go unheard before it's silent by default: 71.4 hours, three of the
  /// sensors' 23.8-hour heartbeat intervals.
  ///
  /// Three intervals let a heartbeat be lost, such as to interference, and the next one
  /// arrive late without the device being reported.
  public static var defaultAllowance: Duration { .seconds(257_040) }

  /// How long a device can go unheard before it's silent.
  public let allowance: Duration

  /// When each watched device was last heard from, or started being watched.
  private var lastHeardAt: [InsteonAddress: Instant] = [:]

  /// Creates a monitor that isn't watching any devices.
  ///
  /// - Parameter allowance: How long a device can go unheard before it's silent. Defaults to
  ///   ``HeartbeatMonitor/defaultAllowance``.
  public init(allowance: Duration = Self.defaultAllowance) {

    self.allowance = allowance

  }

  /// The devices being watched, in address order.
  public var watchedDevices: [InsteonAddress] {

    Self.inAddressOrder(lastHeardAt.keys)

  }

  /// Starts watching a device, counting it as heard from at `instant`.
  ///
  /// Watching a device that's already watched counts it as heard from at `instant` only if
  /// that's later than when it was last heard from, as ``HeartbeatMonitor/heard(from:at:)``
  /// does.
  ///
  /// - Parameters:
  ///   - device: The device to watch.
  ///   - instant: When to start counting from, such as when the app started.
  public mutating func watch(_ device: InsteonAddress, since instant: Instant) {

    lastHeardAt[device] = lastHeardAt[device].map { max($0, instant) } ?? instant

  }

  /// Stops watching a device.
  ///
  /// - Parameter device: The device to stop watching.
  public mutating func stopWatching(_ device: InsteonAddress) {

    lastHeardAt[device] = nil

  }

  /// When a watched device was last heard from, or started being watched.
  ///
  /// - Parameter device: A device.
  /// - Returns: The time, or `nil` if the device isn't watched.
  public func lastHeard(from device: InsteonAddress) -> Instant? {

    lastHeardAt[device]

  }

  /// Notes that a device was heard from.
  ///
  /// A device that isn't watched is ignored, and a message stamped earlier than the last one
  /// heard from the device doesn't move it back.
  ///
  /// - Parameters:
  ///   - device: The device that sent a message.
  ///   - instant: When the message arrived.
  public mutating func heard(from device: InsteonAddress, at instant: Instant) {

    guard let last = lastHeardAt[device] else {

      return

    }

    lastHeardAt[device] = max(last, instant)

  }

  /// The watched devices not heard from for longer than ``HeartbeatMonitor/allowance``.
  ///
  /// - Parameter instant: The time to check at.
  /// - Returns: The silent devices, in address order.
  public func silentDevices(at instant: Instant) -> [InsteonAddress] {

    Self.inAddressOrder(lastHeardAt.filter { $0.value.duration(to: instant) > allowance }.keys)

  }

  /// Orders addresses by their bytes.
  private static func inAddressOrder(_ devices: some Sequence<InsteonAddress>) -> [InsteonAddress] {

    devices.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }

  }

}
