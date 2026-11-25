import InsteonCore
import InsteonModem
import InsteonProtocol
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ScriptedHubTests {

  /// Given a device that broadcasts before the service has started listening, when the service
  /// listens, then it receives the broadcast. A scripted modem that dropped it would leave a test
  /// waiting for a delivery that never comes.
  @Test func holdsABroadcastMadeBeforeAnyoneListensAndHandsItToTheFirstListener() async throws {
    let modem = RecordingModem()
    let device = InsteonAddress(0x1A, 0x2B, 0x3C)

    await modem.broadcastGroupCommand(from: device, group: 2, command1: 0x11)
    var replies = await modem.replies().makeAsyncIterator()

    guard case let .messageReceived(message)? = await replies.next() else {
      Issue.record("The broadcast made before anyone listened was lost.")
      return
    }
    #expect(message.sender == device && message.command.command1 == 0x11)
  }

  /// Given a listener already present, when a device broadcasts, then the listener receives it once.
  @Test func handsABroadcastToAListenerThatIsAlreadyThereOnlyOnce() async throws {
    let modem = RecordingModem()
    let device = InsteonAddress(0x1A, 0x2B, 0x3C)
    var replies = await modem.replies().makeAsyncIterator()

    await modem.broadcastGroupCommand(from: device, group: 2, command1: 0x11)
    await modem.broadcastGroupCommand(from: device, group: 2, command1: 0x13)

    guard case let .messageReceived(first)? = await replies.next(), case let .messageReceived(second)? = await replies.next() else {
      Issue.record("A broadcast was lost.")
      return
    }
    #expect(first.command.command1 == 0x11 && second.command.command1 == 0x13)
  }

}
