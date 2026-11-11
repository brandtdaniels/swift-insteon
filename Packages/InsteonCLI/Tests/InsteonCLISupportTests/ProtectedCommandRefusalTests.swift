import Testing
import InsteonCLISupport
import InsteonCore

/// What the raw passthroughs say, and the status they exit with, when they refuse a protected
/// Set Operating Flags (cmd1 `0x20`), found by its cmd2 alone.
struct ProtectedCommandRefusalTests {

  /// Each protected Set Operating Flags cmd2, as `modem send` takes it, and why it's refused.
  static let refusals: [(command2: UInt8, text: String, consequence: String)] = [
    (0x00, "00", "Locking linking from the device would stop its SET button from linking it"),
    (0x0C, "0C", "Turning radio off would cut the device off the network"),
    (0x0E, "0E", "Turning powerline off would cut the device off the network"),
    (0x19, "19", "Requiring a checksum in every message would cut the device off from a modem that doesn't send one")
  ]

  @Test func deviceSendRefusesEachProtectedSetOperatingFlagsWithItsConsequence() throws {

    for refusal in Self.refusals {

      let command: ProtectedCommand = try #require(ProtectedCommand(command1: 0x20, command2: refusal.command2))
      let sentence: String = SendRefusalText.sentence(.protected(command), from: .deviceSend)

      #expect(sentence == "\(refusal.consequence); insteon sends it only to a device whose catalog entry gives the byte another meaning.")
      #expect(ExitStatus.status(for: CommandFailure(description: sentence)) == ExitStatus.failure)

    }

  }

  @Test func modemSendRefusesEachProtectedSetOperatingFlagsAsAUsageError() {

    for refusal in Self.refusals {

      for forcing in [[], ["--force"]] {

        do {

          _ = try Invocation.parse(["modem", "send", "02621A2B3C0F20\(refusal.text)"] + forcing)
          Issue.record("cmd2 \(refusal.text) was accepted")

        } catch {

          #expect("\(error)" == "\(refusal.consequence); insteon modem send never writes it.", "cmd2 \(refusal.text)")
          #expect(ExitStatus.status(for: error) == ExitStatus.usage, "cmd2 \(refusal.text)")

        }

      }

    }

  }

}
