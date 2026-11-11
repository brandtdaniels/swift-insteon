import Testing
import InsteonCLISupport
import InsteonCore

/// What the raw passthroughs say, and the status they exit with, when they refuse a protected
/// Set Operating Flags (cmd1 `0x20`), found by its cmd2 alone, in protocol terms.
struct ProtectedCommandRefusalTests {

  /// Each protected Set Operating Flags cmd2, as `modem send` takes it and as a sentence names it.
  static let refusals: [(command2: UInt8, text: String, hex: String)] = [
    (0x00, "00", "0x00"),
    (0x0C, "0C", "0x0C"),
    (0x0E, "0E", "0x0E"),
    (0x19, "19", "0x19")
  ]

  /// What every protected Set Operating Flags can do, whatever the device.
  static func protocolFact(_ hex: String) -> String {

    "Set Operating Flags \(hex) can cut a device off from the modem or lock it, depending on the device"

  }

  @Test func deviceSendRefusesEachProtectedSetOperatingFlagsTheCatalogEntryDoesntNameInProtocolTerms() throws {

    for refusal in Self.refusals {

      let command: ProtectedCommand = try #require(ProtectedCommand(command1: 0x20, command2: refusal.command2))
      let sentence: String = SendRefusalText.sentence(.protected(command), from: .deviceSend)

      #expect(sentence == "\(Self.protocolFact(refusal.hex)); insteon sends it only to a device whose catalog entry names the cmd2 for a flag or command it doesn't guard.")
      #expect(ExitStatus.status(for: CommandFailure(description: sentence)) == ExitStatus.failure)

    }

  }

  @Test func modemSendRefusesEachProtectedSetOperatingFlagsInProtocolTermsAsAUsageError() {

    for refusal in Self.refusals {

      for forcing in [[], ["--force"]] {

        do {

          _ = try Invocation.parse(["modem", "send", "02621A2B3C0F20\(refusal.text)"] + forcing)
          Issue.record("cmd2 \(refusal.text) was accepted")

        } catch {

          #expect("\(error)" == "\(Self.protocolFact(refusal.hex)); insteon modem send has no device's catalog entry to check, so it never writes it.", "cmd2 \(refusal.text)")
          #expect(ExitStatus.status(for: error) == ExitStatus.usage, "cmd2 \(refusal.text)")

        }

      }

    }

  }

  @Test func refusesPokeInProtocolTerms() {

    #expect(SendRefusalText.sentence(.protected(.poke), from: .deviceSend) == "Poke One Byte writes any byte of a device's memory, its ALL-Link database included; insteon never sends it.")
    #expect(SendRefusalText.sentence(.protected(.poke), from: .modemSend) == "Poke One Byte writes any byte of a device's memory, its ALL-Link database included; insteon modem send never writes it.")

  }

}
