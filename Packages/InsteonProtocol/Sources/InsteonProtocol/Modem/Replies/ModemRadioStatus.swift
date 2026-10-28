/// The state of a modem's radio, reported in reply to ``SerialCommand/readRadioStatus``.
///
/// Later modem firmware answers with six bytes: its radio frequency code, its radio flags,
/// its LED flags, its hardware version and two more bytes. Insteon's command workbook gives
/// the layout, and the Insteon for Hub app reads the radio flags to tell whether a Hub's radio
/// is off.
public struct ModemRadioStatus: Hashable, Sendable {

  /// The code of the frequency the radio is set to, as Insteon's frequency table gives it.
  public var frequencyCode: UInt8

  /// The radio flags, which ``SerialCommand/setRadio(_:)`` sets.
  public var radioFlags: UInt8

  /// The LED flags.
  public var lightFlags: UInt8

  /// The modem's hardware version.
  public var hardwareVersion: UInt8

  /// The reply's last two bytes, whose meaning Insteon's documents don't settle.
  public var reserved: [UInt8]

  /// Creates a radio status.
  ///
  /// - Parameters:
  ///   - frequencyCode: The frequency code.
  ///   - radioFlags: The radio flags.
  ///   - lightFlags: The LED flags.
  ///   - hardwareVersion: The hardware version.
  ///   - reserved: The reply's last two bytes.
  public init(frequencyCode: UInt8, radioFlags: UInt8, lightFlags: UInt8, hardwareVersion: UInt8, reserved: [UInt8] = [0x00, 0x00]) {

    self.frequencyCode = frequencyCode
    self.radioFlags = radioFlags
    self.lightFlags = lightFlags
    self.hardwareVersion = hardwareVersion
    self.reserved = reserved

  }

  /// Whether the radio is on: bit 0 of ``ModemRadioStatus/radioFlags`` is clear.
  public var isRadioEnabled: Bool {

    radioFlags & 0x01 == 0

  }

}
