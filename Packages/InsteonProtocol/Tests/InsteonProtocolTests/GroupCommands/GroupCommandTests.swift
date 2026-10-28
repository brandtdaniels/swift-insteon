import Testing
import InsteonProtocol

struct GroupCommandTests {

  let keypad = InsteonAddress(0x00, 0x5E, 0x5D)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  let start = ContinuousClock.now

  func broadcast(group: UInt8, command1: UInt8, command2: UInt8 = 0x00, from sender: InsteonAddress? = nil) -> ReceivedMessage {

    ReceivedMessage(
      sender: sender ?? keypad,
      destination: InsteonAddress(0x00, 0x00, group),
      flags: MessageFlags(messageType: .allLinkBroadcast),
      command: Command(command1: command1, command2: command2)
    )

  }

  func cleanup(group: UInt8, command1: UInt8) -> ReceivedMessage {

    ReceivedMessage(
      sender: keypad,
      destination: modem,
      flags: MessageFlags(messageType: .allLinkCleanup),
      command: Command(command1: command1, command2: group)
    )

  }

  @Test func readsABroadcastAndACleanup() {

    #expect(GroupCommand(broadcast(group: 0x03, command1: 0x11, command2: 0xFF))
      == GroupCommand(controller: keypad, group: 0x03, command1: 0x11, command2: 0xFF, source: .broadcast))
    #expect(GroupCommand(cleanup(group: 0x03, command1: 0x11))
      == GroupCommand(controller: keypad, group: 0x03, command1: 0x11, command2: nil, source: .cleanup))

  }

  @Test func readsASuccessReportRatherThanACommand() {

    // Insteon's example: off (0x13) went to the 2 members of group 8, and none failed.
    let report = ReceivedMessage(
      sender: keypad,
      destination: InsteonAddress(0x13, 0x02, 0x08),
      flags: MessageFlags(rawValue: 0xCF),
      command: Command(command1: 0x06, command2: 0x00)
    )

    #expect(GroupCommand(report) == nil)
    #expect(SuccessReport(report) == SuccessReport(controller: keypad, command: 0x13, memberCount: 0x02, group: 0x08, failedCleanups: 0x00))

  }

  @Test func ignoresMessagesThatArentGroupCommands() {

    let direct = ReceivedMessage(sender: keypad, destination: modem, flags: .direct, command: Command(command1: 0x11))

    #expect(GroupCommand(direct) == nil)
    #expect(SuccessReport(direct) == nil)

  }

  @Test func passesOnABroadcastButNotTheCleanupThatFollows() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start)?.source == .broadcast)
    #expect(filter.command(from: cleanup(group: 0x01, command1: 0x11), at: start.advanced(by: .seconds(3))) == nil)

  }

  @Test func passesOnACleanupWhoseBroadcastWasMissed() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: cleanup(group: 0x01, command1: 0x13), at: start.advanced(by: .seconds(5)))?.command1 == 0x13)

  }

  @Test func ignoresARepeatedBroadcastWithinTheWindow() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start.advanced(by: .milliseconds(400))) == nil)
    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start.advanced(by: .seconds(2))) != nil)

  }

  // A later press whose broadcasts were all missed reaches the modem only as a cleanup.
  @Test func passesOnACleanupLongAfterTheSameCommand() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: cleanup(group: 0x01, command1: 0x11), at: start.advanced(by: .seconds(60))) != nil)

  }

  // A retried cleanup for on arrives after the broadcast for off.
  @Test func ignoresALateCleanupForAnEarlierCommand() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x13), at: start.advanced(by: .seconds(2))) != nil)
    #expect(filter.command(from: cleanup(group: 0x01, command1: 0x11), at: start.advanced(by: .seconds(3))) == nil)

  }

  @Test func treatsACleanupAfterTheSuccessReportAsNew() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()
    let report = ReceivedMessage(
      sender: keypad,
      destination: InsteonAddress(0x11, 0x01, 0x01),
      flags: MessageFlags(messageType: .allLinkBroadcast),
      command: Command(command1: 0x06, command2: 0x00)
    )

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: report, at: start.advanced(by: .seconds(2))) == nil)
    #expect(filter.command(from: cleanup(group: 0x01, command1: 0x11), at: start.advanced(by: .seconds(3))) != nil)

  }

  @Test func passesOnABroadcastWithAnotherLevelWithinTheWindow() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11, command2: 0x7F), at: start) != nil)
    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11, command2: 0xFF), at: start.advanced(by: .milliseconds(400))) != nil)

  }

  // A message stamped before the one before it counts as arriving at the same time.
  @Test func treatsAnEarlierStampAsTheSameTime() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start.advanced(by: .milliseconds(-200))) == nil)

  }

  @Test func keepsEachControllersGroupsApart() {

    var filter = GroupCommandFilter<ContinuousClock.Instant>()
    let sensor = InsteonAddress(0x2A, 0x3B, 0x4C)

    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: broadcast(group: 0x02, command1: 0x11), at: start) != nil)
    #expect(filter.command(from: broadcast(group: 0x01, command1: 0x11, from: sensor), at: start) != nil)

  }

}
