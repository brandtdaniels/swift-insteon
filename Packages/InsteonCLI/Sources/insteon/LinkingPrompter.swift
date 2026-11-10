import InsteonCLISupport
import InsteonCore

/// What `insteon link`, `insteon unlink` and `insteon remove` show as a
/// `DeviceLinkingCoordinator` works: what `LinkingOutput.outputs(for:printsJSON:namesProducts:message:)`
/// says to do with each event, progress and instructions on standard error, and results on
/// standard output, or as JSON.
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

    let outputs: [LinkingOutput] = LinkingOutput.outputs(
      for: event,
      printsJSON: printsJSON,
      namesProducts: names.catalog != nil,
      message: Names.message(for:)
    )

    for output in outputs {

      switch output {
      case .saveIdentities:
        await cached.save()
      case let .line(text):
        Output.line(text)
      case let .table(rows):
        Output.table(rows)
      case let .note(text):
        Output.note(text)
      case let .json(report):
        do {

          try Output.json(report)

        } catch {

          Output.note(Names.message(for: error))

        }
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

}
