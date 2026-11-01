import InsteonCore

/// Writes what the data bytes of an ALL-Link database record hold, as the MEANING column of
/// `insteon device ADDRESS links` prints them.
public enum LinkDataText {

  /// The explained bytes, each with what it holds, such as
  /// `"On-level 0xFF (On), Ramp rate 0x1F"`.
  ///
  /// A byte is named by its label, or else its name, then its value, then the value's name
  /// from its table, or for the responder's own group, "its group" and the number. A byte
  /// whose value differs from the one the catalog gives for it says so, such as
  /// `"On-level 0x00 (the catalog gives 0xFE)"`.
  ///
  /// - Parameter explanation: What the catalog says the record's bytes hold.
  /// - Returns: The text.
  public static func meaning(of explanation: LinkDataMeaning) -> String {

    let parts: [String] = explanation.bytes.map { (byte: LinkDataField) -> String in

      var notes: [String] = []

      if let valueName = byte.valueName {

        notes.append(valueName)

      } else if byte.isPerGroup {

        notes.append("its group \(byte.value)")

      }

      if let documented = byte.documentedValue, documented != byte.value {

        notes.append("the catalog gives \(Hex.byte(documented))")

      }

      let name: String = byte.label ?? byte.name
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
  ///   - isDeviceInCatalog: Whether the Insteon device catalog has the device's product.
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
  ///   - responderCount: How many responders the modem's ALL-Link database lists for the
  ///     group, if known. With none, the modem's report says nothing about responders.
  /// - Returns: The lines, in order: how many acknowledged, or what the modem reported when
  ///   none were seen; then those that didn't; then whether the modem stopped partway.
  public static func cleanup(
    acknowledged: [InsteonAddress],
    unacknowledged: [InsteonAddress],
    isComplete: Bool,
    responderCount: Int? = nil
  ) -> [String] {

    var lines: [String] = []

    if !acknowledged.isEmpty {

      lines.append("\(Wording.count(acknowledged.count, "device")) acknowledged the cleanup.")

    } else if isComplete && responderCount != 0 {

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
