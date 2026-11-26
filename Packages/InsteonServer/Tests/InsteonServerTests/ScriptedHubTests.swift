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

  /// Given a connection that an earlier attempt waited on and was canceled while waiting, as a
  /// run that lost its port to another suite is, when a later attempt waits on the same
  /// connection and the test then drops it, then the later attempt sees the drop. A connection
  /// that ended for everyone when one waiter left would end the later attempt at once.
  @Test func aConnectionStaysUpForALaterAttemptAfterAnEarlierOneWasCanceled() async throws {
    let link = HubLink()
    let earlier = Task { try await link.waitUntilDropped() }

    earlier.cancel()
    _ = await earlier.result

    let later = Task { () -> String in
      do {
        try await link.waitUntilDropped()
        return "returned"
      } catch {
        return "\(error)"
      }
    }

    // Wait, by yielding and not by time, until the later attempt is parked on the connection.
    while link.waiterCount == 0 { await Task.yield() }

    link.drop(with: ScriptedHubOpener.StillAway())

    #expect(await later.value == "\(ScriptedHubOpener.StillAway())")
  }

  /// Given a connection dropped before anyone waits, when an attempt waits, then it sees the drop.
  @Test func aConnectionDroppedBeforeAnyoneWaitsEndsTheNextWaiter() async throws {
    let link = HubLink()

    link.drop(with: ScriptedHubOpener.StillAway())

    await #expect(throws: ScriptedHubOpener.StillAway.self) { try await link.waitUntilDropped() }
  }

}
