import InsteonCLISupport
import InsteonCore

/// `insteon device ADDRESS send` and `insteon modem send`: messages and serial commands sent
/// as given, for exploring what the Insteon device catalog doesn't describe yet, through
/// InsteonCore's `DeviceNetwork` and `ModemSession`, which refuse what's never sent. What they
/// print, and in what order, is `RawSendFlow`.
enum ExploreCommands {

  static func send(_ request: DirectMessageRequest, to device: InsteonAddress, network: DeviceNetwork) async throws {

    try await RawSendFlow.deviceSend(request, to: device, through: network, output: TerminalOutput())

  }

  static func send(_ request: RawSerialRequest, modem: ModemSession) async throws {

    try await RawSendFlow.modemSend(request, through: modem, output: TerminalOutput())

  }

}

/// The terminal: progress to standard error, results to standard output.
struct TerminalOutput: CommandOutput {

  func note(_ text: String) {

    Output.note(text)

  }

  func line(_ text: String) {

    Output.line(text)

  }

}
