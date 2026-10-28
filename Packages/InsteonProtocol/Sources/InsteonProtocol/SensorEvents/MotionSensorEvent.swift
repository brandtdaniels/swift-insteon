/// What a motion sensor reports to its groups, as Insteon's PIR III command sheet gives them.
///
/// A sensor reports each event as an on (`0x11`) or off (`0x13`) to a group. Some sensors
/// report an event's end as an on to an alternate group instead of an off, which this type reads
/// the same way.
///
/// ```swift
/// if let command = filter.command(from: message, at: .now), let event = MotionSensorEvent(command) {
///   print(event)   // "motion"
/// }
/// ```
public enum MotionSensorEvent: Hashable, Sendable {

  /// Motion was detected: on to group 1.
  case motion

  /// No motion since the sensor's timeout: off to group 1, or on to group 5.
  case motionStopped

  /// It got dark: on to group 2.
  case dark

  /// It got light: off to group 2, or on to group 6.
  case light

  /// The battery is low: on to group 3.
  case lowBattery

  /// The sensor's periodic heartbeat, to group 4.
  case heartbeat

  /// Reads a motion sensor's event from a group command.
  ///
  /// - Parameter command: A command the sensor sent.
  /// - Returns: `nil` if the command isn't one of the events above.
  public init?(_ command: GroupCommand) {

    switch (command.group.rawValue, command.command1) {
    case (0x01, 0x11): self = .motion
    case (0x01, 0x13), (0x05, 0x11): self = .motionStopped
    case (0x02, 0x11): self = .dark
    case (0x02, 0x13), (0x06, 0x11): self = .light
    case (0x03, 0x11): self = .lowBattery
    case (0x04, _): self = .heartbeat
    default: return nil
    }

  }

}
