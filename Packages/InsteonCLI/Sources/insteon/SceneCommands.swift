import InsteonCLICore
import InsteonModem
import InsteonProtocol

/// `insteon scene` and `insteon beep`: what the modem does itself.
enum SceneCommands {

  // MARK: - scene

  static func scene(_ group: AllLinkGroupNumber, isOn: Bool, modem: Modem) async throws {

    Output.note("Reading the modem's ALL-Link database...")

    // The modem controls the group's devices, each of which keeps a responder record for it.
    let records: [AllLinkRecord] = try await modem.allLinkRecords()
    let members: [InsteonAddress] = records.filter { $0.flags.contains(.controller) && $0.group == group }.map(\.address)
    let responders: [InsteonAddress] = Array(Set(members)).sorted { $0.description < $1.description }
    let commandName: String = isOn ? "Light On" : "Light Off"

    if responders.isEmpty {

      Output.note("The modem's ALL-Link database lists no responders for group \(group); sending anyway.")

    }

    let command: Command = isOn ? StandardDirectCommand.on(level: 0xFF).command : StandardDirectCommand.off.command
    // The Insteon Developer's Guide gives up to 2.150 seconds to the first cleanup and 1.550
    // seconds to each one after.
    let seconds: Int = max(10, 3 + 2 * responders.count)
    let report: AllLinkCleanupReport

    do {

      report = try await modem.sendAllLinkCommand(group: group, command: command, timeout: .seconds(seconds))

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
