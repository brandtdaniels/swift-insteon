import InsteonCLISupport
import InsteonCore
import InsteonModem
import InsteonProtocol

/// `insteon scene` and `insteon beep`: what the modem does itself.
enum SceneCommands {

  // MARK: - scene

  static func scene(_ group: AllLinkGroupNumber, isOn: Bool, modem: Modem) async throws {

    Output.note("Reading the modem's ALL-Link database...")

    // The modem controls the group's devices, each of which keeps a responder record for it.
    let scene: ModemScene = ModemScene(group: group)
    let responders: [InsteonAddress] = try await scene.responders(in: modem)
    let commandName: String = isOn ? "Light On" : "Light Off"

    if responders.isEmpty {

      Output.note("The modem's ALL-Link database lists no responders for group \(group); sending anyway.")

    }

    let report: AllLinkCleanupReport

    do {

      report = try await scene.send(turningOn: isOn, responderCount: responders.count, through: modem)

    } catch ModemError.rejected {

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

  static func beep(isDouble: Bool, modem: Modem) async throws {

    let name: String = isDouble ? "a double beep" : "Beep"

    do {

      try await modem.send(isDouble ? .doubleBeep : .beep)

    } catch let error as ModemError {

      switch error {
      case .rejected, .timedOut:
        throw CommandFailure(description: "The modem doesn't support \(name): it \(isRejection(error) ? "rejected it" : "didn't answer").")
      default:
        throw error
      }

    }

    Output.line(isDouble ? "The modem beeped twice." : "The modem beeped.")

  }

  private static func isRejection(_ error: ModemError) -> Bool {

    if case .rejected = error {

      return true

    }

    return false

  }

}
