/// The modem's configuration flags, set with ``SerialCommand/setModemConfiguration(_:)``.
public struct ModemConfiguration: OptionSet, Hashable, Sendable {

  /// The flags byte.
  public let rawValue: UInt8

  /// Creates configuration flags from a flags byte.
  ///
  /// - Parameter rawValue: The flags byte.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// Disables the host deadman timer, allowing more than 240 ms between bytes from the host
  /// (bit 4).
  public static let disableDeadman = ModemConfiguration(rawValue: 1 << 4)

  /// Disables automatic control of the modem's LED, leaving it to the host (bit 5).
  public static let disableAutomaticLED = ModemConfiguration(rawValue: 1 << 5)

  /// Puts the modem in monitor mode, so it reports messages addressed to other devices (bit 6).
  public static let monitorMode = ModemConfiguration(rawValue: 1 << 6)

  /// Disables linking by pressing and holding the modem's SET button (bit 7).
  public static let disableAutomaticLinking = ModemConfiguration(rawValue: 1 << 7)

}
