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

    } catch {

      if let failure = SceneText.failure(SendFailure(error), group: group, isOn: isOn) {

        throw CommandFailure(description: failure)

      }

      throw error

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

    do {

      try await modem.beep(isDouble: isDouble)

    } catch {

      if let failure = SceneText.beepFailure(SendFailure(error), isDouble: isDouble) {

        throw CommandFailure(description: failure)

      }

      throw error

    }

    Output.line(isDouble ? "The modem beeped twice." : "The modem beeped.")

  }

}
