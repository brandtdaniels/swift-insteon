import InsteonCLISupport
import InsteonCore

/// `insteon scene` and `insteon beep`: what the modem does itself.
enum SceneCommands {

  // MARK: - scene

  static func scene(_ group: AllLinkGroupNumber, isOn: Bool, modem: ModemSession) async throws {

    Output.note("Reading the modem's ALL-Link database...")

    // The modem controls the group's devices, each of which keeps a responder record for it.
    let scene: ModemScene = ModemScene(group: group)
    let responders: [InsteonAddress] = try await scene.responders(in: modem)
    let commandName: String = isOn ? "Light On" : "Light Off"

    if responders.isEmpty {

      Output.note("The modem's ALL-Link database lists no responders for group \(group); sending anyway.")

    }

    let report: SceneResult

    do {

      report = try await scene.send(turningOn: isOn, responderCount: responders.count, through: modem)

    } catch where SendFailure(error) == .modemRejected {

      throw CommandFailure(description: "The modem rejected \(commandName) for group \(group); it does that for a group it has no records for.")

    }

    Output.line("Sent \(commandName) to group \(group). The modem's ALL-Link database lists \(Wording.count(responders.count, "responder")) for it.")

    let lines: [String] = SceneText.cleanup(
      acknowledged: report.acknowledged,
      unacknowledged: report.unacknowledged,
      isComplete: report.isComplete,
      responderCount: responders.count
    )

    for line in lines {

      Output.line(line)

    }

  }

  // MARK: - beep

  static func beep(isDouble: Bool, modem: ModemSession) async throws {

    let name: String = isDouble ? "a double beep" : "Beep"

    do {

      try await modem.beep(isDouble: isDouble)

    } catch {

      switch SendFailure(error) {
      case .modemRejected?:
        throw CommandFailure(description: "The modem doesn't support \(name): it rejected it.")
      case .modemUnanswered?:
        throw CommandFailure(description: "The modem doesn't support \(name): it didn't answer.")
      default:
        throw error
      }

    }

    Output.line(isDouble ? "The modem beeped twice." : "The modem beeped.")

  }

}
