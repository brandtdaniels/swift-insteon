/// Finds battery-powered devices that have gone quiet, such as a leak sensor whose battery
/// died or that was moved out of range.
///
/// Sensors send a heartbeat periodically, so a sensor that hasn't been heard from in much
/// longer than that has likely stopped working. Insteon's heartbeat status sheet gives the
/// interval as 23.8 hours for the leak, open/close and motion sensors, with the first
/// heartbeat as late as 23.8 hours after the batteries go in. A device is silent once nothing
/// has been heard from it for ``HeartbeatMonitor/allowance``.
///
/// Any message counts, not only a heartbeat: the sheet notes that a sensor restarts its
/// heartbeat interval when its button is pressed, so a sensor that's in use may send no
/// heartbeat for longer than the interval.
///
/// The monitor keeps no clock of its own: give it the time each message arrived and the time
/// to check, from any clock, so tests can use one they control.
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

  /// How long a device can go unheard before it's silent by default: 47.6 hours, two of the
  /// heartbeat intervals Insteon's heartbeat status sheet gives.
  ///
  /// Two intervals let one heartbeat be lost, such as to interference, without the device
  /// being reported.
  public static var defaultAllowance: Duration { .seconds(171_360) }

  /// How long a device can go unheard before it's silent.
  public let allowance: Duration

  /// When each watched device was last heard from, or started being watched.
  private var lastHeard: [InsteonAddress: Instant] = [:]

  /// Creates a monitor that isn't watching any devices.
  ///
  /// - Parameter allowance: How long a device can go unheard before it's silent. Defaults to
  ///   ``HeartbeatMonitor/defaultAllowance``.
  public init(allowance: Duration = Self.defaultAllowance) {

    self.allowance = allowance

  }

  /// The devices being watched, in address order.
  public var watchedDevices: [InsteonAddress] {

    lastHeard.keys.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }

  }

  /// Starts watching a device, counting it as heard from at `instant`.
  ///
  /// Watching a device that's already watched counts it as heard from again.
  ///
  /// - Parameters:
  ///   - device: The device to watch.
  ///   - instant: When to start counting from, such as when the app started.
  public mutating func watch(_ device: InsteonAddress, since instant: Instant) {

    lastHeard[device] = instant

  }

  /// Stops watching a device.
  ///
  /// - Parameter device: The device to stop watching.
  public mutating func stopWatching(_ device: InsteonAddress) {

    lastHeard[device] = nil

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

    guard let last = lastHeard[device] else {

      return

    }

    lastHeard[device] = max(last, instant)

  }

  /// The watched devices not heard from for longer than ``HeartbeatMonitor/allowance``.
  ///
  /// - Parameter instant: The time to check at.
  /// - Returns: The silent devices, in address order.
  public func silentDevices(at instant: Instant) -> [InsteonAddress] {

    watchedDevices.filter { device in

      lastHeard[device].map { $0.duration(to: instant) > allowance } ?? false

    }

  }

}
