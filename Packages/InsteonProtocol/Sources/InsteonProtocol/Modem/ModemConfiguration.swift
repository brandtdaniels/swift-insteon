/// The modem's configuration flags, set with ``SerialCommand/setModemConfiguration(_:)``.
///
/// All flags default to off. Setting the configuration replaces every flag at once, so read
/// the current flags with ``SerialCommand/getModemConfiguration`` before changing one.
///
/// The Developer's Guide reserves bits 0–3. The Insteon Hub 2242 Developer's Guide gives bit 3
/// a meaning and reserves bits 0–2, and Insteon's command workbook shows other firmware using
/// bit 2 to ignore X10 and bits 0 and 1 for options it names without describing, so leave the
/// bits you don't set as the modem reports them.
public struct ModemConfiguration: OptionSet, Hashable, Sendable {

  /// The flags byte.
  public let rawValue: UInt8

  /// Creates configuration flags from a flags byte.
  ///
  /// - Parameter rawValue: The flags byte.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// NAKs serial commands while the modem is busy sending an Insteon message (bit 3), as the
  /// Insteon Hub 2242 Developer's Guide describes.
  public static let negativeAcknowledgeWhenBusy = ModemConfiguration(rawValue: 1 << 3)

  /// Ignores X10 (bit 2), on later modem firmware.
  public static let disableX10 = ModemConfiguration(rawValue: 1 << 2)

  /// Disables the host deadman timer, allowing more than 240 ms between bytes from the host
  /// (bit 4). Without it, the modem discards a command whose bytes arrive too slowly.
  public static let disableDeadman = ModemConfiguration(rawValue: 1 << 4)

  /// Disables automatic control of the modem's LED, leaving it to the host (bit 5).
  ///
  /// Required before ``SerialCommand/ledOn`` and ``SerialCommand/ledOff``, which the modem
  /// otherwise NAKs.
  public static let disableAutomaticLED = ModemConfiguration(rawValue: 1 << 5)

  /// Puts the modem in monitor mode (bit 6).
  ///
  /// Normally the modem only reports messages addressed to it or to a group it responds to. In
  /// monitor mode it also reports any message sent by a device in its ALL-Link database, even
  /// when the message is addressed to another device.
  public static let monitorMode = ModemConfiguration(rawValue: 1 << 6)

  /// Disables linking by pressing and holding the modem's SET button (bit 7).
  public static let disableAutomaticLinking = ModemConfiguration(rawValue: 1 << 7)

}
