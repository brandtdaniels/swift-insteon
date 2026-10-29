import InsteonDeviceCatalog
import InsteonProtocol

/// What `insteon device ADDRESS on` and `status` send and print, by what the device's group
/// type says it is.
///
/// A relay turns only on and off, so it's sent a full Light On whatever level was asked for,
/// and its status reads as on or off rather than a percentage. A device whose kind isn't known
/// is treated as a dimmer, as before the catalog was consulted.
public enum ControlText {

  /// The level to send with Light On.
  ///
  /// - Parameters:
  ///   - percent: The level asked for, from 0 to 100, or `nil` for fully on.
  ///   - kind: The kind of the device's main group, if known.
  /// - Returns: `0xFF` for a relay or for fully on, and otherwise the level for the percentage.
  public static func level(percent: Int?, kind: GroupType.Kind?) -> UInt8 {

    guard let percent, kind != .relay else {

      return 0xFF

    }

    return LightLevel.level(percent: percent)

  }

  /// What to print after Light On.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - percent: The level asked for, or `nil` for fully on.
  ///   - kind: The kind of the device's main group, if known.
  /// - Returns: A line such as "Turned 1A.2B.3C on at 50%.", or for a relay asked for a level,
  ///   "1A.2B.3C is on/off only; turned it on."
  public static func turnedOn(_ device: InsteonAddress, percent: Int?, kind: GroupType.Kind?) -> String {

    guard let percent else {

      return "Turned \(device) on."

    }

    guard kind == .relay else {

      return "Turned \(device) on at \(percent)%."

    }

    return percent == 100 ? "Turned \(device) on." : "\(device) is on/off only; turned it on."

  }

  /// What to print for the level a Light Status Request reported.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - level: The level, from the acknowledgment's cmd2.
  ///   - kind: The kind of the device's main group, if known.
  /// - Returns: "1A.2B.3C is on." or "is off." for a relay, and otherwise the level as a
  ///   percentage, such as "1A.2B.3C is on at 50% (level 0x80)."
  public static func status(_ device: InsteonAddress, level: UInt8, kind: GroupType.Kind?) -> String {

    if kind == .relay {

      return "\(device) is \(level == 0 ? "off" : "on")."

    }

    let percent = LightLevel.percent(level: level)

    return "\(device) is \(percent == 0 ? "off" : "on at \(percent)%") (level \(Hex.byte(level)))."

  }

}

/// Writes what the data bytes of an ALL-Link database record hold, as the MEANING column of
/// `insteon device ADDRESS links` prints them.
public enum LinkDataText {

  /// The explained bytes, each with what it holds, such as
  /// `"On-level 0xFF (On), Ramp rate 0x1F"`.
  ///
  /// A byte is named by its label, or else its name, then its value, then the value's name
  /// from its table, or for the responder's own group, "its group" and the number.
  ///
  /// - Parameter explanation: What the catalog says the record's bytes hold.
  /// - Returns: The text.
  public static func meaning(of explanation: RecordDataExplanation) -> String {

    let parts: [String] = explanation.bytes.map { byte in

      var text = "\(byte.label ?? byte.name.rawValue) \(Hex.byte(byte.value))"

      if let entry = byte.tableEntry {

        text += " (\(entry.label))"

      } else if byte.isPerGroup {

        text += " (its group \(byte.value))"

      }

      return text

    }

    return parts.joined(separator: ", ")

  }

}
