import InsteonCore
import InsteonProtocol

/// What `insteon device ADDRESS on`, `status` and the other commands sent through a `Device`
/// print. The library says what the device did and what it is; this only words it.
public enum DeviceText {

  /// What to print after turning a device on, with Light On or Light On Fast.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - result: What turning it on did.
  /// - Returns: "Turned 1A.2B.3C on at 50%." for a level a group took, "1A.2B.3C is on/off
  ///   only; turned it on." for one it couldn't take, other than 100%, and otherwise
  ///   "Turned 1A.2B.3C on."
  public static func turnedOn(_ device: InsteonAddress, result: DeviceTurnOnResult) -> String {

    if let ignored = result.ignoredLevel, ignored != 100 {

      return "\(device) is on/off only; turned it on."

    }

    if let level = result.level {

      return "Turned \(device) on at \(level)%."

    }

    return "Turned \(device) on."

  }

  /// What to print after turning a device off, with Light Off or Light Off Fast.
  ///
  /// - Parameter device: The device.
  /// - Returns: "Turned 1A.2B.3C off."
  public static func turnedOff(_ device: InsteonAddress) -> String {

    "Turned \(device) off."

  }

  /// What to print after Light Instant Change.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - result: What the change did.
  /// - Returns: "Changed 1A.2B.3C to 50% at once." for a group that dims; and for one that's
  ///   on/off only, "Turned 1A.2B.3C off." for 0%, "Turned 1A.2B.3C on." for 100%, and
  ///   otherwise "1A.2B.3C is on/off only; turned it on."
  public static func changedInstantly(_ device: InsteonAddress, result: DeviceInstantChangeResult) -> String {

    guard result.isOnOffOnly else {

      return "Changed \(device) to \(result.level)% at once."

    }

    if result.level == 0 {

      return turnedOff(device)

    }

    return result.level == 100 ? "Turned \(device) on." : "\(device) is on/off only; turned it on."

  }

  /// The note to print when the Insteon device catalog doesn't describe a device's commands,
  /// so the command the Insteon protocol defines was sent.
  ///
  /// - Parameter command: The command's name, such as "Light On Fast".
  /// - Returns: The note.
  public static func undescribedCommandNote(_ command: String) -> String {

    "The Insteon device catalog doesn't describe this device's commands; sending \(command) anyway."

  }

  /// What to print after Beep.
  ///
  /// - Parameter device: The device.
  /// - Returns: "1A.2B.3C beeped."
  public static func beeped(_ device: InsteonAddress) -> String {

    "\(device) beeped."

  }

  /// The note to print when the device's command set doesn't list Beep, which is sent anyway.
  public static let unlistedBeepNote: String = "The Insteon device catalog doesn't list Beep for this device; sending anyway."

  /// What to print when a device rejected Beep.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - reason: The reason it gave.
  /// - Returns: A sentence such as "1A.2B.3C rejected Beep (NAK): it isn't linked to the
  ///   modem."
  public static func beepRejected(_ device: InsteonAddress, reason: NAKReason) -> String {

    "\(device) rejected Beep (NAK): \(reason.summary)."

  }

  /// What to print when a device didn't answer Beep.
  ///
  /// - Parameter device: The device.
  /// - Returns: The sentence.
  public static func beepUnanswered(_ device: InsteonAddress) -> String {

    "\(device) didn't answer Beep. Check that it's powered and in range."

  }

  /// What to print for a device's status.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - status: The status.
  /// - Returns: A level as a percentage, such as "1A.2B.3C is on at 50% (level 0x80).", on or
  ///   off, such as "1A.2B.3C is on.", the name of the value's range, such as
  ///   "1A.2B.3C is medium.", or the byte alone, "1A.2B.3C reports level 0x80."
  public static func status(_ device: InsteonAddress, status: DeviceStatus) -> String {

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
  public static func failure(_ error: DeviceControlError, device: InsteonAddress) -> String {

    let passthrough: String = "'insteon device \(device) send' sends it a message as given."

    switch error {
    case let .notIdentified(operation):
      return "\(device) didn't report its identity, so the Insteon device catalog can't say how to \(phraseForIt(operation)). "
        + "Check that it's linked and in range; \(passthrough)"
    case .notLinked:
      // As the modem's error for a device's NAK words it.
      return "Device \(device) rejected the command: \(NAKReason.notLinked.summary)."
    case let .unsupported(operation, product):
      if let command = commandName(operation) {

        return "The Insteon device catalog doesn't list \(command) for \(product)."

      }

      return "Neither the Insteon device catalog nor the device's category says how to \(phrase(operation)) \(product). \(passthrough)"
    case let .noSuchGroup(group, product):
      return "\(product) has no group \(group) to control."
    case let .missingCommand(name, product):
      return "The Insteon device catalog names a command '\(name)' for \(product) but doesn't describe it."
    case let .unaddressable(operation, group, product):
      return "The Insteon device catalog gives no command that can \(phrase(operation)) group \(group) of \(product) on its own; "
        + "its command reaches another group. \(passthrough)"
    }

  }

  /// The name of the one command an operation sends, for an operation that must be listed in
  /// the device's command set, or `nil`.
  private static func commandName(_ operation: DeviceOperation) -> String? {

    switch operation {
    case .turnOnFast:
      "Light On Fast"
    case .turnOffFast:
      "Light Off Fast"
    case .instantChange:
      "Light Instant Change"
    case .beep:
      "Beep"
    case .turnOn, .turnOff, .status, .settings:
      nil
    }

  }

  /// What an operation does to "it", the device, such as "turn it on".
  private static func phraseForIt(_ operation: DeviceOperation) -> String {

    switch operation {
    case .turnOn, .turnOnFast:
      "turn it on"
    case .turnOff, .turnOffFast:
      "turn it off"
    case .instantChange:
      "change its level"
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
    case .turnOn, .turnOnFast:
      "turn on"
    case .turnOff, .turnOffFast:
      "turn off"
    case .instantChange:
      "change the level of"
    case .status:
      "read the status of"
    case .beep:
      "beep"
    case .settings:
      "read the settings of"
    }

  }

}
