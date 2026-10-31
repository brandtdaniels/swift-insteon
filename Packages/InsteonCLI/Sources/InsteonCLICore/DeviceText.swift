import InsteonCLICore
import InsteonCore
import InsteonProtocol

/// What `insteon device ADDRESS on`, `status` and the other commands sent through a `Device`
/// print. The library says what the device did and what it is; this only words it.
enum DeviceText {

  /// What to print after turning a device on.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - result: What turning it on did.
  /// - Returns: "Turned 1A.2B.3C on at 50%." for a level a group took, "1A.2B.3C is on/off
  ///   only; turned it on." for one it couldn't take, other than 100%, and otherwise
  ///   "Turned 1A.2B.3C on."
  static func turnedOn(_ device: InsteonAddress, result: DeviceTurnOnResult) -> String {

    if let ignored = result.ignoredLevel, ignored != 100 {

      return "\(device) is on/off only; turned it on."

    }

    if let level = result.level {

      return "Turned \(device) on at \(level)%."

    }

    return "Turned \(device) on."

  }

  /// What to print for a device's status.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - status: The status.
  /// - Returns: A level as a percentage, such as "1A.2B.3C is on at 50% (level 0x80).", on or
  ///   off, such as "1A.2B.3C is on.", the name of the value's range, such as
  ///   "1A.2B.3C is medium.", or the byte alone, "1A.2B.3C reports level 0x80."
  static func status(_ device: InsteonAddress, status: DeviceStatus) -> String {

    switch status.reading {
    case let .percent(percent):
      "\(device) is \(percent == 0 ? "off" : "on at \(percent)%") (level \(Hex.byte(status.value)))."
    case let .onOff(isOn):
      "\(device) is \(isOn ? "on" : "off")."
    case let .named(label):
      "\(device) is \(label.lowercased())."
    case .raw:
      "\(device) reports level \(Hex.byte(status.value))."
    }

  }

  /// Why the library couldn't do what was asked, as a sentence.
  ///
  /// - Parameters:
  ///   - error: The library's refusal.
  ///   - device: The device.
  /// - Returns: The sentence.
  static func failure(_ error: DeviceControlError, device: InsteonAddress) -> String {

    let passthrough: String = "'insteon device \(device) send' sends it a message as given."

    switch error {
    case let .notIdentified(operation):
      return "\(device) didn't report its identity, so the Insteon device catalog can't say how to \(phraseForIt(operation)). "
        + "Check that it's linked and in range; \(passthrough)"
    case let .unsupported(.beep, product):
      return "The Insteon device catalog doesn't list Beep for \(product)."
    case let .unsupported(operation, product):
      return "Neither the Insteon device catalog nor the device's category says how to \(phrase(operation)) \(product). \(passthrough)"
    case let .noSuchGroup(group, product):
      return "\(product) has no group \(group) to control."
    case let .missingCommand(name, product):
      return "The Insteon device catalog names a command '\(name)' for \(product) but doesn't describe it."
    }

  }

  /// What an operation does to "it", the device, such as "turn it on".
  private static func phraseForIt(_ operation: DeviceOperation) -> String {

    switch operation {
    case .turnOn:
      "turn it on"
    case .turnOff:
      "turn it off"
    case .status:
      "read its status"
    case .beep:
      "make it beep"
    case .settings:
      "read its settings"
    }

  }

  /// What an operation does, as a verb phrase that takes the device after it.
  private static func phrase(_ operation: DeviceOperation) -> String {

    switch operation {
    case .turnOn:
      "turn on"
    case .turnOff:
      "turn off"
    case .status:
      "read the status of"
    case .beep:
      "beep"
    case .settings:
      "read the settings of"
    }

  }

}
