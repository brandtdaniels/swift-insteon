import InsteonLinking
import InsteonModem
import InsteonProtocol
import Testing

@testable import InsteonDemo

/// The demo modem answers as a modem and devices do, for the few commands the service sends.
@Suite(.timeLimit(.minutes(1)))
struct DemoModemTests {
  private let lamp = DemoNetwork.lamp
  private let modem = DemoModem()

  private func status(of device: InsteonAddress) async throws -> UInt8 {
    let reply = try await modem.request(StandardMessage(to: device, command: Command(command1: 0x19, command2: 0x00)), timeout: .seconds(1))
    return reply.command.command2
  }

  @Test func aDeviceStartsOff() async throws {
    #expect(try await status(of: lamp) == 0x00)
  }

  @Test func lightOnSetsTheLevelTheNextStatusReports() async throws {
    _ = try await modem.request(StandardMessage(to: lamp, command: Command(command1: 0x11, command2: 0xFF)), timeout: .seconds(1))

    #expect(try await status(of: lamp) == 0xFF)
  }

  @Test func lightOnAtALevelDimsToIt() async throws {
    _ = try await modem.request(StandardMessage(to: lamp, command: Command(command1: 0x11, command2: 0x80)), timeout: .seconds(1))

    #expect(try await status(of: lamp) == 0x80)
  }

  @Test func lightOffTurnsItOff() async throws {
    _ = try await modem.request(StandardMessage(to: lamp, command: Command(command1: 0x11, command2: 0xFF)), timeout: .seconds(1))
    _ = try await modem.request(StandardMessage(to: lamp, command: Command(command1: 0x13, command2: 0x00)), timeout: .seconds(1))

    #expect(try await status(of: lamp) == 0x00)
  }

  @Test func aDeviceThatIsNotInTheDemoDoesNotAnswer() async {
    let stranger = InsteonAddress(0x01, 0x02, 0x03)

    await #expect(throws: ModemError.deviceTimedOut(stranger)) {
      _ = try await modem.request(StandardMessage(to: stranger, command: Command(command1: 0x19, command2: 0x00)), timeout: .seconds(1))
    }
  }

  @Test func theModemControlsTheScenesAndEachMemberRespondsToThem() async throws {
    let records = try await modem.allLinkRecords()
    let scenes = Dictionary(grouping: records.filter { $0.flags.contains(.controller) }, by: \.group)

    #expect(scenes.count >= 2)
    #expect(scenes.values.allSatisfy { $0.count >= 1 })

    let member = try #require(scenes.values.first?.first).address
    let database = try await modem.readAllLinkDatabase(of: member, timeout: .seconds(1))
    let responders = database.filter { $0.record.flags.contains(.inUse) && !$0.record.flags.contains(.controller) }

    #expect(!responders.isEmpty)
    #expect(database.last?.isEndOfDatabase == true)
  }
}
