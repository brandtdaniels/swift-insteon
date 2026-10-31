import InsteonCLICore
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking

/// What `insteon link` and `insteon unlink` show as a `DeviceLinkingCoordinator` works: its
/// progress and instructions on standard error, worded by `LinkingEventText`, and each link
/// made or removed on standard output, or as JSON.
///
/// When the device goes first, the instructions end by asking for Return when standard input
/// is a terminal, and the modem joins once it's pressed; Control-C stops the wait.
struct LinkingPrompter: LinkingObserver {

  /// The catalog's product names, for the identity printed with a link made.
  let names: ProductNames

  /// Whether the results are printed as JSON. A link's JSON is printed by the command once
  /// both legs are done; a removed link's as it's reported.
  let printsJSON: Bool

  func linking(_ event: LinkingEvent) async {

    switch event {
    case let .linked(linked):
      guard !printsJSON else {

        return

      }

      // The first leg prints the device's identity, and the link back the link alone.
      ModemCommands.report(linked.link, known: linked.leg == .first ? linked.device?.deviceDescription : nil, names: names)
    case let .unlinked(unlinked):
      report(unlinked)
    case let .unlinkedAll(removed):
      report(removed)
    default:
      for line in LinkingEventText.notes(for: event, message: Names.message(for:)) {

        Output.note(line)

      }
    }

  }

  func waitUntilDeviceIsReady(_ prompt: DeviceFirstPrompt) async throws {

    let waits: Bool = Terminal.readsFromTerminal

    for line in LinkingEventText.deviceFirst(prompt, waitsForReturn: waits) {

      Output.note(line)

    }

    if waits {

      try await Terminal.waitForReturn()

    }

  }

  /// Prints a removed link. A removed link carries no identity, so the device is named only
  /// if it was known before.
  private func report(_ unlinked: UnlinkedLink) {

    let link: AllLinkingCompleted = unlinked.link
    let known: DeviceDescription? = unlinked.device?.deviceDescription

    if printsJSON {

      json(ModemCommands.Unlink(address: "\(link.address)", group: Int(link.group.rawValue), product: known?.displayName))

    } else {

      Output.line("Unlinked \(LinkingInstructions.deviceLabel(link.address, profile: known?.profile)) from group \(link.group).")

    }

  }

  /// Prints the links removed without the device's SET button.
  private func report(_ removed: RemovedLinks) {

    let known: DeviceDescription? = removed.device?.deviceDescription
    let label: String = LinkingInstructions.deviceLabel(removed.address, profile: known?.profile)
    let reports: [ModemCommands.RemovedLink] = removed.links.map { (link: ModemLink) -> ModemCommands.RemovedLink in

      ModemCommands.RemovedLink(
        address: "\(removed.address)",
        group: Int(link.group.rawValue),
        modemRole: link.modemRole == .controller ? "controller" : "responder",
        product: known?.displayName
      )

    }

    if printsJSON {

      json(reports)

    } else if reports.isEmpty {

      Output.line("The modem has no links with \(label).")

    } else {

      for report in reports {

        Output.line("Unlinked \(label) from group \(report.group), modem as \(report.modemRole).")

      }

    }

  }

  /// Prints a value as JSON, or says why it couldn't be.
  private func json(_ value: some Encodable) {

    do {

      try Output.json(value)

    } catch {

      Output.note("insteon: \(Names.message(for: error))")

    }

  }

}
