import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// What `insteon modem send` and `insteon device ADDRESS send` print, and in what order: the
/// line that says bytes are going out comes only once the send is allowed, so a refused send
/// prints only its refusal.
struct RawSendOutputTests {

  /// The lines a command printed, in order, each with the stream it went to.
  final class Transcript: CommandOutput, @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] {

      lock.withLock { recorded }

    }

    func note(_ text: String) {

      lock.withLock { recorded.append("note: \(text)") }

    }

    func line(_ text: String) {

      lock.withLock { recorded.append("line: \(text)") }

    }

  }

  /// A modem that decides as InsteonCore does: it refuses without calling `onWriting`, or calls
  /// it and answers.
  struct StubModem: RawCommandWriting {

    /// What it refuses, or `nil` to allow every command.
    var refusal: SendRefusal?

    /// Whether `--force` lifts the refusal.
    var isLiftedByForce = false

    var replies: [RawModemReply] = []

    func writeRaw(_ bytes: [UInt8], forcing: Bool, collectingFor duration: Duration, onWriting: @Sendable () -> Void) async throws -> [RawModemReply] {

      if let refusal, !(isLiftedByForce && forcing) {

        throw refusal

      }

      onWriting()

      return replies

    }

  }

  /// A network that decides as InsteonCore does.
  struct StubNetwork: DirectMessageSending {

    var refusal: SendRefusal?

    func sendDirect(
      _ message: DirectMessage,
      collectingFor duration: Duration,
      consent: SendConsent,
      onSending: @Sendable () -> Void,
      onAcknowledgment: @Sendable (ReceivedFrame) -> Void
    ) async throws -> [ReceivedFrame] {

      if let refusal {

        throw refusal

      }

      onSending()

      return []

    }

  }

  static let device = InsteonAddress(0x3A, 0x4B, 0x01)

  /// Runs `modem send` and returns what it printed and the failure it ended with.
  static func modemSend(_ request: RawSerialRequest, through modem: StubModem) async -> (lines: [String], failure: String?) {

    let transcript = Transcript()
    var failure: String?

    do {

      try await RawSendFlow.modemSend(request, through: modem, output: transcript)

    } catch {

      failure = "\(error)"

    }

    return (transcript.lines, failure)

  }

  /// Runs `device ADDRESS send` and returns what it printed and the failure it ended with.
  static func deviceSend(_ request: DirectMessageRequest, through network: StubNetwork) async -> (lines: [String], failure: String?) {

    let transcript = Transcript()
    var failure: String?

    do {

      try await RawSendFlow.deviceSend(request, to: device, through: network, output: transcript)

    } catch {

      failure = "\(error)"

    }

    return (transcript.lines, failure)

  }

  // MARK: - modem send

  @Test(.timeLimit(.minutes(1))) func aModemSendTheCommandNeedsConsentForPrintsOnlyTheRefusal() async {

    let refusal: SendRefusal = .needsConsent(.configuration)
    let result = await Self.modemSend(RawSerialRequest(bytes: [0x02, 0x6B, 0x43]), through: StubModem(refusal: refusal, isLiftedByForce: true))

    #expect(result.lines.isEmpty)
    #expect(result.failure == SendRefusalText.sentence(refusal, from: .modemSend))

  }

  @Test(.timeLimit(.minutes(1))) func aModemSendTheFloorRefusesPrintsOnlyTheRefusal() async {

    for refusal in [SendRefusal.neverSentToModem, .serialCommand("The command number isn't one the package knows.")] {

      let result = await Self.modemSend(RawSerialRequest(bytes: [0x02, 0x09], isForced: true), through: StubModem(refusal: refusal))

      #expect(result.lines.isEmpty)
      #expect(result.failure == SendRefusalText.sentence(refusal, from: .modemSend))

    }

  }

  @Test(.timeLimit(.minutes(1))) func anAllowedModemSendPrintsTheWritingLineOnceBeforeTheReplies() async {

    let replies: [RawModemReply] = [.echo(bytes: [0x02, 0x60, 0x06], kind: "Example echo"), .negativeAcknowledgment]
    let result = await Self.modemSend(RawSerialRequest(bytes: [0x02, 0x60]), through: StubModem(replies: replies))

    #expect(result.lines == ["note: Writing 02 60 to the modem", "line: 02 60 06  Example echo", "line: 15  NAK"])
    #expect(result.failure == nil)

  }

  @Test(.timeLimit(.minutes(1))) func aForcedModemSendPrintsTheWritingLine() async {

    let consent: StubModem = StubModem(refusal: .needsConsent(.destructive), isLiftedByForce: true)

    let refused = await Self.modemSend(RawSerialRequest(bytes: [0x02, 0x67]), through: consent)
    let forced = await Self.modemSend(RawSerialRequest(bytes: [0x02, 0x67], isForced: true), through: consent)

    #expect(refused.lines.isEmpty)
    #expect(forced.lines == ["note: Writing 02 67 to the modem", "line: The modem sent nothing in 3 s."])
    #expect(forced.failure == nil)

  }

  // MARK: - device ADDRESS send

  @Test(.timeLimit(.minutes(1))) func aDeviceSendTheCatalogRefusesPrintsOnlyTheRefusal() async {

    let refusal: SendRefusal = .needsConsent(.destructive)
    let result = await Self.deviceSend(DirectMessageRequest(command1: 0x55, command2: 0x00), through: StubNetwork(refusal: refusal))

    #expect(result.lines.isEmpty)
    #expect(result.failure == SendRefusalText.sentence(refusal, from: .deviceSend))

  }

  @Test(.timeLimit(.minutes(1))) func anAllowedDeviceSendPrintsTheSendingLineOnceBeforeTheMessages() async {

    let standard = await Self.deviceSend(DirectMessageRequest(command1: 0x19, command2: 0x00), through: StubNetwork())
    let extended = await Self.deviceSend(DirectMessageRequest(command1: 0x2E, command2: 0x00, userData: [0x01, 0x02]), through: StubNetwork())

    #expect(standard.lines == ["note: Sending 3A.4B.01 cmd1 0x19 cmd2 0x00", "line: No other messages from 3A.4B.01 in 3 s."])
    #expect(extended.lines.first?.hasPrefix("note: Sending 3A.4B.01 extended cmd1 0x2E cmd2 0x00, data 01 02") == true)
    #expect(extended.lines.count == 2)

  }

}
