import InsteonCore

/// What `insteon remove` asks and prints, from what a `DeviceLinkingCoordinator` reports as it
/// removes a device.
public enum RemovalText {

  /// The question asked before a device is removed.
  ///
  /// - Parameters:
  ///   - device: The device, as `LinkingInstructions.deviceLabel(_:profile:)` writes it.
  ///   - forcesModemSide: Whether `--force-modem-side` was given.
  /// - Returns: The question, ending with its choices.
  public static func question(device: String, forcesModemSide: Bool) -> String {

    let removal: String = "Remove \(device) from the network? Its links with the modem are removed and the identity cache forgets it."

    guard forcesModemSide else {

      return "\(removal) [y/N]"

    }

    return "\(removal) If it doesn't answer, the modem's records for it are deleted anyway, "
      + "which is only right for a device that's gone. [y/N]"

  }

  /// What to say when the person answers no.
  ///
  /// - Parameter device: The device, as `LinkingInstructions.deviceLabel(_:profile:)` writes it.
  /// - Returns: The message.
  public static func declined(device: String) -> String {

    "\(device) wasn't removed."

  }

  /// What to say when a device's links couldn't be removed through it, so it wasn't removed.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - device: The device, as `LinkingInstructions.deviceLabel(_:profile:)` writes it.
  ///   - reason: Why a link couldn't be removed, as a sentence that ends with a period.
  /// - Returns: The message.
  public static func notRemoved(_ address: InsteonAddress, device: String, reason: String) -> String {

    "\(device) wasn't removed: its links with the modem couldn't be removed without its SET button. \(reason) "
      + "Remove the links that are left with its SET button, then run 'insteon remove \(address)' again. "
      + "If the device is gone for good, 'insteon remove \(address) --force-modem-side' deletes the modem's records for it instead."

  }

  /// Why the modem's records for a device are being deleted directly, as a sentence that ends
  /// with a period.
  ///
  /// - Parameters:
  ///   - device: The device's address.
  ///   - reason: Why the records are being deleted.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The sentence.
  public static func deletionReason(_ device: InsteonAddress, _ reason: ModemRecordDeletionReason, message: (any Error) -> String) -> String {

    switch reason {
    case .noAnswer:
      return "\(device) didn't answer."
    case .remoteLinkingUnsupported:
      return "\(device) can't be unlinked without its SET button, since its engine doesn't take Enter Unlinking Mode."
    case let .remoteUnlinkingFailed(error):
      return "\(device)'s links couldn't be removed through it: \(message(error))"
    case let .linksLeft(links):
      return "The modem still has \(Wording.count(links.count, "link")) with \(device): \(describe(links))."
    case let .modemLinksUnreadable(error):
      return "The modem's ALL-Link database couldn't be read to check \(device)'s links are gone: \(message(error))"
    }

  }

  /// The modem's records deleted directly for a device that's gone.
  ///
  /// - Parameters:
  ///   - device: The device's address.
  ///   - records: The records deleted, in the modem's order.
  /// - Returns: The lines.
  public static func modemRecordsDeleted(_ device: InsteonAddress, _ records: [LinkRecord]) -> [String] {

    guard !records.isEmpty else {

      return ["The modem had no records for \(device) to delete."]

    }

    return records.map { (record: LinkRecord) -> String in

      "Deleted the modem's \(role(record)) record for \(device) in group \(record.group)."

    }

  }

  /// Why a device was kept rather than removed, as a sentence that ends with a period.
  ///
  /// - Parameters:
  ///   - device: The device's address.
  ///   - reason: Why it was kept.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The sentence.
  public static func keptReason(_ device: InsteonAddress, _ reason: DeviceKeptReason, message: (any Error) -> String) -> String {

    switch reason {
    case let .linksRemain(links):
      return "The modem still has \(Wording.count(links.count, "link")) with \(device): \(describe(links))."
    case let .modemLinksUnreadable(error):
      return "The modem's ALL-Link database couldn't be read to check its links are gone: \(message(error))"
    case let .modemRecordsNotDeleted(error):
      return "The modem's records for it couldn't all be deleted: \(message(error))"
    }

  }

  /// What to say when a device was kept in the identity cache because its links with the
  /// modem aren't confirmed gone.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - device: The device, as `LinkingInstructions.deviceLabel(_:profile:)` writes it.
  ///   - reason: Why it was kept.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The message.
  public static func kept(_ address: InsteonAddress, device: String, reason: DeviceKeptReason, message: (any Error) -> String) -> String {

    let why: String = keptReason(address, reason, message: message)
    let next: String

    switch reason {
    case .linksRemain:
      next = "Remove them with 'insteon unlink \(address)' and the device's SET button, then run 'insteon remove \(address)' again; "
        + "if the device is gone for good, run 'insteon remove \(address) --force-modem-side'."
    case .modemLinksUnreadable:
      next = "Run 'insteon remove \(address)' again."
    case .modemRecordsNotDeleted:
      next = "Run 'insteon remove \(address) --force-modem-side' again."
    }

    return "\(device) was kept, not removed. \(why) \(next)"

  }

  /// Links between the modem and a device, such as `"controller in group 0, responder in
  /// group 1"`.
  static func describe(_ links: [ModemLink]) -> String {

    links.map { (link: ModemLink) -> String in

      "\(link.modemRole == .controller ? "controller" : "responder") in group \(link.group)"

    }.joined(separator: ", ")

  }

  /// What to say once the identity cache forgot the device.
  ///
  /// - Parameter forgotten: The device forgotten.
  /// - Returns: The lines.
  public static func forgotten(_ forgotten: ForgottenDevice) -> [String] {

    ["Removed \(label(forgotten.address, forgotten.device)) from the network, and the identity cache forgot it."]

  }

  /// What other devices still hold that names a removed device, and which databases couldn't
  /// be read.
  ///
  /// - Parameters:
  ///   - scan: What was found.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The lines.
  public static func leftoverRecords(_ scan: LeftoverRecordScan, message: (any Error) -> String) -> [String] {

    let removed: String = "\(scan.removedDevice)"
    var lines: [String] = []

    if scan.holders.isEmpty && scan.unread.isEmpty {

      return ["No other device the identity cache knows holds records for \(removed)."]

    }

    for holder in scan.holders {

      let records: [String] = holder.records.map { (record: LinkRecord) -> String in

        "\(role(record)) in group \(record.group) at \(record.memoryAddress.map(Hex.address) ?? "an unknown address")"

      }

      lines.append(
        "\(label(holder.address, holder.device)) still holds \(Wording.count(records.count, "record")) for \(removed): "
          + records.joined(separator: "; ") + "."
      )

    }

    if !scan.holders.isEmpty {

      lines.append("Those records weren't changed. Removing \(removed) from those devices' scenes clears them.")

    }

    for unread in scan.unread {

      lines.append(
        "Couldn't read the ALL-Link database of \(label(unread.address, unread.device)), so it may hold records for \(removed) too: "
          + message(unread.reason)
      )

    }

    return lines

  }

  /// How to restore a removed device's factory settings, with the catalog's steps.
  ///
  /// - Parameter reset: The catalog's reset steps for the device.
  /// - Returns: The lines.
  public static func factoryReset(_ reset: FactoryResetSteps) -> [String] {

    let device: String = LinkingInstructions.deviceLabel(reset.address, profile: reset.deviceDescription?.profile)

    guard let procedure = reset.procedure, !procedure.steps.isEmpty else {

      return [
        "The Insteon device catalog has no factory reset steps for \(device); its owner's manual has them. "
          + "A reset erases the links the device keeps itself. The command doesn't reset it."
      ]

    }

    var lines: [String] = ["To restore the factory settings of \(device), which the command doesn't do:"]

    lines += LinkingInstructions.steps(procedure.steps).enumerated().map { (step: (offset: Int, element: String)) -> String in

      "  \(step.offset + 1). \(step.element)"

    }

    let erased: [String] = erasures(reset.erases)

    if !erased.isEmpty {

      lines.append("A factory reset erases \(erased.joined(separator: " and ")).")

    }

    lines += procedure.notes.map { (note: String) -> String in "Note: \(note)" }

    return lines

  }

  /// What a factory reset erases, in the order the catalog lists the kinds, as the help
  /// words them, such as `"its ALL-Link database"`.
  ///
  /// - Parameter erases: What the catalog says a reset erases.
  /// - Returns: The phrases.
  public static func erasures(_ erases: Set<LifecycleErasure>) -> [String] {

    let phrases: [(erasure: LifecycleErasure, phrase: String)] = [
      (erasure: .links, phrase: "its ALL-Link database"),
      (erasure: .settings, phrase: "its settings")
    ]

    return phrases.filter { (entry: (erasure: LifecycleErasure, phrase: String)) -> Bool in

      erases.contains(entry.erasure)

    }.map { (entry: (erasure: LifecycleErasure, phrase: String)) -> String in

      entry.phrase

    }

  }

  /// A device's address, with its product when it's known.
  private static func label(_ address: InsteonAddress, _ device: RegisteredDevice?) -> String {

    LinkingInstructions.deviceLabel(address, profile: device?.deviceDescription.profile)

  }

  /// A record's role in its device's database.
  static func role(_ record: LinkRecord) -> String {

    record.isController ? "controller" : "responder"

  }

}
