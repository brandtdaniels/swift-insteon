import InsteonCore

/// One thing `insteon link`, `insteon unlink` or `insteon remove` does with an event a
/// `DeviceLinkingCoordinator` reports.
public enum LinkingOutput: Hashable, Sendable {

  /// Save the identities the network learned to the cache, so a second Control-C, which
  /// ends the command at once, doesn't lose them.
  case saveIdentities

  /// Print a line on standard output.
  case line(String)

  /// Print rows of columns on standard output.
  case table([[String]])

  /// Print a line on standard error.
  case note(String)

  /// Write the links made as JSON on standard output.
  case json(LinkingJSON.LinkReport)

  /// What to do with an event, in order.
  ///
  /// The first link of a device saves the identity it reported. Progress and instructions are
  /// notes, worded by ``LinkingEventText/notes(for:message:)``. Each link made or removed, a
  /// device forgotten, the records other devices hold for it and its factory reset steps are
  /// lines, left out with `--json`, where the command prints them from what the coordinator
  /// returns. With `--json`, the links made before linking from a Hub stopped are written as
  /// JSON, since the command then fails without a result.
  ///
  /// - Parameters:
  ///   - event: The event.
  ///   - printsJSON: Whether the command prints JSON.
  ///   - namesProducts: Whether the command has a catalog, so a link's identity names its
  ///     product.
  ///   - message: The sentence that describes an error.
  /// - Returns: What to do.
  public static func outputs(for event: LinkingEvent, printsJSON: Bool, namesProducts: Bool, message: (any Error) -> String) -> [LinkingOutput] {

    func notes() -> [LinkingOutput] {

      LinkingEventText.notes(for: event, message: message).map(LinkingOutput.note)

    }

    func lines(_ lines: [String]) -> [LinkingOutput] {

      printsJSON ? [] : lines.map(LinkingOutput.line)

    }

    switch event {
    case let .linked(linked):
      let saves: [LinkingOutput] = linked.leg == .first ? [.saveIdentities] : []

      guard !printsJSON else {

        return saves

      }

      // The first leg prints the device's identity, and the link back the link alone.
      return saves + self.linked(linked.link, known: linked.leg == .first ? linked.device?.info : nil, namesProducts: namesProducts)
    case let .unlinked(unlinked):
      // A removed link carries no identity, so the device is named only if it was known.
      let label: String = LinkingInstructions.deviceLabel(unlinked.link.address, info: unlinked.device?.info)

      return lines(["Unlinked \(label) from group \(unlinked.link.group)."])
    case let .unlinkedAll(removed):
      return lines(removedLines(removed))
    case let .forgotten(forgotten):
      return lines(RemovalText.forgotten(forgotten))
    case let .leftoverRecords(scan):
      return lines(RemovalText.leftoverRecords(scan, message: message))
    case let .modemRecordsDeleted(device, records):
      return lines(RemovalText.modemRecordsDeleted(device, records))
    case let .factoryReset(reset):
      return lines(RemovalText.factoryReset(reset))
    case let .hubLinkingStopped(result, _):
      // The links made before linking stopped, so --json shows them with the error.
      return (printsJSON ? [.json(LinkingJSON.report(result, message: message))] : []) + notes()
    default:
      return notes()
    }

  }

  /// A link made, with the device's identity when it's known: its category, subcategory and
  /// firmware, and its product when the command has a catalog.
  private static func linked(_ link: LinkMade, known: DeviceInfo?, namesProducts: Bool) -> [LinkingOutput] {

    let line: LinkingOutput = .line("Linked \(link.address) in group \(link.group), modem as \(Names.mode(link.mode)).")

    guard let known else {

      return [line]

    }

    var rows: [[String]] = [
      ["Category:", Names.category(known.category)],
      ["Subcategory:", "\(known.subcategory)"],
      ["Firmware:", known.firmwareVersion.map { "\($0)" } ?? "not reported"]
    ]

    if namesProducts {

      rows.append(["Product:", known.displayName ?? "not in the Insteon device catalog"])

    }

    return [line, .table(rows)]

  }

  /// The links removed without the device's SET button, or that there were none.
  private static func removedLines(_ removed: RemovedLinks) -> [String] {

    let label: String = LinkingInstructions.deviceLabel(removed.address, info: removed.device?.info)
    let reports: [LinkingJSON.RemovedLink] = LinkingJSON.removedLinks(removed)

    guard !reports.isEmpty else {

      return ["The modem has no links with \(label)."]

    }

    return reports.map { (report: LinkingJSON.RemovedLink) -> String in "Unlinked \(label) from group \(report.group), modem as \(report.modemRole)." }

  }

}
