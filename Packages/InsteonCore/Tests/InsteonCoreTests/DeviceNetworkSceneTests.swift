import Foundation
import Testing
@testable import InsteonCore
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Running one of the modem's scenes through a network: one group command, then the cleanups.
@Suite(.timeLimit(.minutes(1)))
struct DeviceNetworkSceneTests {

  private func network(_ modem: InMemoryModem) -> DeviceNetwork {

    DeviceNetwork(modem: modem, catalog: nil, clock: TestClock())

  }

  private func controllers(_ group: AllLinkGroupNumber, of devices: [InsteonAddress]) -> [AllLinkRecord] {

    devices.map { AllLinkRecord(flags: [.inUse, .controller], group: group, address: $0, data1: 0, data2: 0, data3: 0) }

  }

  @Test func sendsTheGroupLightOnAtFullLevelAndGivesTheCleanupReport() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords(controllers(3, of: [Example.lamp, Example.plug]))
    await modem.setGroupReport(AllLinkCleanupReport(acknowledged: [Example.lamp], unacknowledged: [Example.plug], isComplete: true))

    let result: SceneResult = try await network(modem).run(ModemScene(group: 3), turningOn: true)

    #expect(result == SceneResult(acknowledged: [Example.lamp], unacknowledged: [Example.plug], isComplete: true, responderCount: 2))
    #expect(await modem.groupCommands == [InMemoryModem.GroupCommand(group: 3, command: Command(command1: 0x11, command2: 0xFF), wait: .standard)])

  }

  @Test func sendsLightOffToTurnTheGroupOff() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords(controllers(3, of: [Example.lamp]))

    _ = try await network(modem).run(ModemScene(group: 3), turningOn: false)

    #expect(await modem.groupCommands.map(\.command) == [Command(command1: 0x13, command2: 0x00)])

  }

  @Test func passesOnTheWaitItWasGiven() async throws {

    let modem = InMemoryModem()
    let wait: AllLinkCleanupWait = AllLinkCleanupWait(echo: .seconds(7), quietPeriod: .seconds(11), cap: .seconds(90))
    await modem.setModemRecords(controllers(3, of: [Example.lamp]))

    _ = try await network(modem).run(ModemScene(group: 3), turningOn: true, wait: wait)

    #expect(await modem.groupCommands.map(\.wait) == [wait])

  }

  @Test func reportsHowManyControllerRecordsTheModemHoldsSoAResponderThatDoesNotAnswerIsCounted() async throws {

    let modem = InMemoryModem()
    // The lamp answers; the plug is a controller record too, but nothing reads or answers for it.
    await modem.setModemRecords(controllers(3, of: [Example.lamp, Example.plug]) + controllers(4, of: [Example.sensor]))
    await modem.setUnanswering(Example.plug)

    let result: SceneResult = try await network(modem).run(ModemScene(group: 3), turningOn: true)

    #expect(result.responderCount == 2)

  }

  @Test func countsTheResponderOnceWhenTheModemHoldsTwoRecordsForIt() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords(controllers(3, of: [Example.lamp, Example.lamp]))

    _ = try await network(modem).run(ModemScene(group: 3), turningOn: true)

    #expect(await modem.groupCommands.count == 1)

  }

  @Test func readsTheModemsDatabaseOnlyWhenTheNetworkHoldsNoCopy() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords(controllers(3, of: [Example.lamp]))
    let network: DeviceNetwork = network(modem)

    _ = try await network.modemDatabase()
    let reads: Int = await modem.modemDatabaseReads
    _ = try await network.run(ModemScene(group: 3), turningOn: true)
    _ = try await network.run(ModemScene(group: 3), turningOn: false)

    #expect(await modem.modemDatabaseReads == reads)

  }

  @Test func sendsOnlyTheGroupCommandAndNothingToAnyDevice() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords(controllers(3, of: [Example.lamp]))

    _ = try await network(modem).run(ModemScene(group: 3), turningOn: true)

    #expect(await modem.writes.isEmpty)
    #expect(await modem.levels.isEmpty)
    #expect(await modem.linkingSteps.isEmpty)

  }

  @Test func throwsTheModemsRefusalForAGroupItHasNoRecordsFor() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords(controllers(3, of: [Example.lamp]))

    await #expect(throws: ModemError.rejected(.sendAllLinkCommand)) {

      try await network(modem).run(ModemScene(group: 9), turningOn: true)

    }
    #expect(await modem.groupCommands.isEmpty)

  }

  @Test func throwsCancellationFromACanceledTaskWithoutSending() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords(controllers(3, of: [Example.lamp]))
    let network: DeviceNetwork = network(modem)

    let task = Task {

      withUnsafeCurrentTask { $0?.cancel() }

      return try await network.run(ModemScene(group: 3), turningOn: true)

    }

    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await modem.groupCommands.isEmpty)

  }

}
