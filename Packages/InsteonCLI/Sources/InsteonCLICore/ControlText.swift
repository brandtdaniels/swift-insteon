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

  /// The level to send with Light Instant Change.
  ///
  /// - Parameters:
  ///   - percent: The level asked for, from 0 to 100.
  ///   - kind: The kind of the device's main group, if known.
  /// - Returns: For a relay, `0x00` for 0% and otherwise `0xFF`, since it's on/off only; and
  ///   otherwise the level for the percentage.
  public static func instantLevel(percent: Int, kind: GroupType.Kind?) -> UInt8 {

    guard kind == .relay else {

      return LightLevel.level(percent: percent)

    }

    return percent == 0 ? 0x00 : 0xFF

  }

  /// What to print after Light Instant Change.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - percent: The level asked for.
  ///   - kind: The kind of the device's main group, if known.
  /// - Returns: A line such as "Changed 1A.2B.3C to 50% at once.", or for a relay,
  ///   "1A.2B.3C is on/off only; turned it on."
  public static func changedInstantly(_ device: InsteonAddress, percent: Int, kind: GroupType.Kind?) -> String {

    guard kind == .relay else {

      return "Changed \(device) to \(percent)% at once."

    }

    if percent == 0 {

      return "Turned \(device) off."

    }

    return percent == 100 ? "Turned \(device) on." : "\(device) is on/off only; turned it on."

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
  /// from its table, or for the responder's own group, "its group" and the number. A byte
  /// whose value differs from the one the catalog gives for it says so, such as
  /// `"On-level 0x00 (the documents give 0xFE)"`.
  ///
  /// - Parameter explanation: What the catalog says the record's bytes hold.
  /// - Returns: The text.
  public static func meaning(of explanation: RecordDataExplanation) -> String {

    let parts: [String] = explanation.bytes.map { (byte: RecordDataExplanation.DataByte) -> String in

      var notes: [String] = []

      if let entry = byte.tableEntry {

        notes.append(entry.label)

      } else if byte.isPerGroup {

        notes.append("its group \(byte.value)")

      }

      if let documented = byte.documentedValue, documented != byte.value {

        notes.append("the documents give \(Hex.byte(documented))")

      }

      let name: String = byte.label ?? byte.name.rawValue
      let text: String = "\(name) \(Hex.byte(byte.value))"

      return notes.isEmpty ? text : "\(text) (\(notes.joined(separator: "; ")))"

    }

    return parts.joined(separator: ", ")

  }

  /// What the MEANING column of `insteon device ADDRESS links` shows for a record.
  ///
  /// - Parameters:
  ///   - meaning: What ``meaning(of:)`` wrote for the record, or `nil` if the catalog doesn't
  ///     explain its bytes.
  ///   - isController: Whether it's a controller record.
  ///   - isDeviceInCatalog: Whether the Insteon device catalog has the device's profile.
  /// - Returns: The meaning; or "not documented" for a controller record of a device the
  ///   catalog has but gives no controller data bytes for; or else an empty string.
  public static func column(meaning: String?, isController: Bool, isDeviceInCatalog: Bool) -> String {

    if let meaning {

      return meaning

    }

    return isController && isDeviceInCatalog ? "not documented" : ""

  }

}

/// What `insteon scene` prints about the ALL-Link cleanup that follows an ALL-Link Recall.
///
/// Some modems, such as the Hub 2245's, don't pass the responders' cleanup acknowledgments up
/// to the host, and send only their ALL-Link Cleanup Status Report. So no acknowledgments
/// doesn't mean no responder answered.
public enum SceneText {

  /// The lines that say how the cleanup went.
  ///
  /// - Parameters:
  ///   - acknowledged: The responders seen to acknowledge their cleanup.
  ///   - unacknowledged: The responders the modem reported didn't.
  ///   - isComplete: Whether the modem's ALL-Link Cleanup Status Report says it sent every
  ///     responder its cleanup.
  /// - Returns: The lines, in order: how many acknowledged, or what the modem reported when
  ///   none were seen; then those that didn't; then whether the modem stopped partway.
  public static func cleanup(acknowledged: [InsteonAddress], unacknowledged: [InsteonAddress], isComplete: Bool) -> [String] {

    var lines: [String] = []

    if !acknowledged.isEmpty {

      lines.append("\(Wording.count(acknowledged.count, "device")) acknowledged the cleanup.")

    } else if isComplete {

      let others: String = unacknowledged.isEmpty ? "every responder" : "every other responder"

      lines.append("The modem reports \(others) answered its cleanup.")

    }

    if !unacknowledged.isEmpty {

      let addresses: [String] = unacknowledged.map { (address: InsteonAddress) -> String in "\(address)" }

      lines.append("Didn't acknowledge: \(addresses.joined(separator: ", ")).")

    }

    if !isComplete {

      lines.append("The modem says it didn't reach every responder.")

    }

    return lines

  }

}
