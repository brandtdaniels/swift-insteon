import InsteonCLISupport
import InsteonCore

/// What `insteon link`, `insteon unlink` and `insteon remove` show as a
/// `DeviceLinkingCoordinator` works: its progress and instructions on standard error, worded
/// by `LinkingEventText`, and each link made or removed, a device forgotten, the records other
/// devices hold for it and its factory reset steps on standard output, or as JSON.
///
/// When the device goes first, the instructions end by asking for Return when standard input
/// is a terminal, and the modem joins once it's pressed; Control-C stops the wait.
///
/// The identity a link reports is saved to the cache as soon as the link asked for is made,
/// as `insteon links --identify` saves each identity it learns, so a second Control-C during
/// the link back, which ends the command at once, doesn't lose it.
struct LinkingPrompter: LinkingObserver {

  /// The catalog's product names, for the identity printed with a link made.
  let names: ProductNames

  /// Whether the results are printed as JSON, which the command prints from what the
  /// coordinator returns, so a JSON encoding failure fails the command. The prompter then
  /// prints only notes.
  let printsJSON: Bool

  /// The network whose cache keeps the identities devices report.
  let cached: CachedNetwork

  func linking(_ event: LinkingEvent) async {

    switch event {
    case let .linked(linked):
      if linked.leg == .first {

        await cached.save()

      }

      guard !printsJSON else {

        return

      }

      // The first leg prints the device's identity, and the link back the link alone.
      ModemCommands.report(linked.link, known: linked.leg == .first ? linked.device?.deviceDescription : nil, names: names)
    case let .unlinked(unlinked):
      if !printsJSON {

        report(unlinked)

      }
    case let .unlinkedAll(removed):
      if !printsJSON {

        report(removed)

      }
    case let .forgotten(forgotten):
      if !printsJSON {

        lines(RemovalText.forgotten(forgotten))

      }
    case let .leftoverRecords(scan):
      if !printsJSON {

        lines(RemovalText.leftoverRecords(scan, message: Names.message(for:)))

      }
    case let .modemRecordsDeleted(device, records):
      if !printsJSON {

        lines(RemovalText.modemRecordsDeleted(device, records))

      }
    case let .hubLinkingStopped(result, _):
      // The links made before linking stopped, so --json shows them with the error.
      if printsJSON {

        do {

          try Output.json(LinkingJSON.report(result, message: Names.message(for:)))

        } catch {

          Output.note(Names.message(for: error))

        }

      }

      for line in LinkingEventText.notes(for: event, message: Names.message(for:)) {

        Output.note(line)

      }
    case let .factoryReset(reset):
      if !printsJSON {

        lines(RemovalText.factoryReset(reset))

      }
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

  func waitUntilDeviceIsAwake(_ prompt: WakePrompt) async throws {

    let waits: Bool = Terminal.readsFromTerminal

    for line in LinkingEventText.wake(prompt, waitsForReturn: waits) {

      Output.note(line)

    }

    if waits {

      try await Terminal.waitForReturn()

    }

  }

  /// Prints lines on standard output.
  private func lines(_ lines: [String]) {

    for line in lines {

      Output.line(line)

    }

  }

  /// Prints a removed link. A removed link carries no identity, so the device is named only
  /// if it was known before.
  private func report(_ unlinked: UnlinkedLink) {

    let link: AllLinkingCompleted = unlinked.link
    let known: DeviceDescription? = unlinked.device?.deviceDescription

    Output.line("Unlinked \(LinkingInstructions.deviceLabel(link.address, profile: known?.profile)) from group \(link.group).")

  }

  /// Prints the links removed without the device's SET button.
  private func report(_ removed: RemovedLinks) {

    let known: DeviceDescription? = removed.device?.deviceDescription
    let label: String = LinkingInstructions.deviceLabel(removed.address, profile: known?.profile)
    let reports: [LinkingJSON.RemovedLink] = LinkingJSON.removedLinks(removed)

    guard !reports.isEmpty else {

      Output.line("The modem has no links with \(label).")

      return

    }

    for report in reports {

      Output.line("Unlinked \(label) from group \(report.group), modem as \(report.modemRole).")

    }

  }

}
