/// A FanLinc's fan speed.
///
/// The FanLinc controls its light as group 1, like a dimmer, and its fan as group 2. Insteon's
/// command workbook sets the fan with an extended on whose D1 is `0x02`; turning it off sends
/// an extended off with the same D1, as the dual outlet's second relay is turned off. The
/// speed is read with a status request with variant `0x03`, whose acknowledgement carries the
/// speed in cmd2:
///
/// ```swift
/// try await modem.request(ExtendedMessage(to: fan, command: FanSpeed.medium.command, userData: FanSpeed.userData))
///
/// let ack = try await modem.request(StandardMessage(to: fan, command: StandardDirectCommand.statusRequest(variant: 0x03)))
/// print(FanSpeed(level: ack.command.command2))
/// ```
public enum FanSpeed: Hashable, Sendable, CaseIterable {

  /// The fan is off.
  case off

  /// Low speed.
  case low

  /// Medium speed.
  case medium

  /// High speed.
  case high

  /// The user data that addresses the fan rather than the light: `0x02` in D1.
  public static var userData: UserData {

    var userData = UserData()
    userData[1] = 0x02

    return userData

  }

  /// Reads a speed from the level a FanLinc reports.
  ///
  /// Insteon's command workbook gives `0x00` as off, `0x01` to `0x7F` as low, `0x80` to `0xFE`
  /// as medium and `0xFF` as high.
  ///
  /// - Parameter level: The level, such as the cmd2 of a status request's acknowledgement.
  public init(level: UInt8) {

    switch level {
    case 0x00: self = .off
    case 0x01...0x7F: self = .low
    case 0x80...0xFE: self = .medium
    default: self = .high
    }

  }

  /// The level that sets the speed: `0x00`, `0x55`, `0xAA` or `0xFF`, each within the range
  /// ``FanSpeed/init(level:)`` reads as the same speed.
  public var level: UInt8 {

    switch self {
    case .off: 0x00
    case .low: 0x55
    case .medium: 0xAA
    case .high: 0xFF
    }

  }

  /// The command that sets the speed: off (cmd1 `0x13`) for ``FanSpeed/off``, and on (cmd1
  /// `0x11`) at ``FanSpeed/level`` otherwise. Send it with ``FanSpeed/userData``.
  public var command: Command {

    self == .off ? Command(command1: 0x13, command2: 0x00) : Command(command1: 0x11, command2: level)

  }

}
