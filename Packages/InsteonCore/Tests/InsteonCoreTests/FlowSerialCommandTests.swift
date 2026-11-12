import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// The serial commands InsteonCore's flows send a modem, with the flows run on an in-memory
/// modem: each flow completes, and every command it sends is one the flows declare, so
/// a raw send's policy is no stricter than a flow's own consent for it.
struct FlowSerialCommandTests {

  let clock: TestClock = TestClock()

  /// The serial commands a flow sends, in order.
  actor Sent {

    private(set) var commands: [SerialCommand] = []

    func record(_ operation: InMemoryModem.Operation) {

      if case let .send(command) = operation {

        commands.append(command)

      }

    }

  }

  func network(_ modem: InMemoryModem) async -> DeviceNetwork {

    await modem.setModemRecords(RemovalExample.lampRecords + [RemovalExample.keypadRecord])
    await modem.setRecordsLinks()

    let snapshot = NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [RemovalExample.lamp: RemovalExample.lampIdentity, RemovalExample.keypad: RemovalExample.keypadIdentity]),
      devices: [RemovalExample.lamp: NetworkDeviceState(engine: .i2cs, allLinkDatabase: AllLinkDatabaseCopy(delta: 0x00, records: []), level: 0xFF, lastSeen: Date(timeIntervalSince1970: 1_700_000_000))],
      modemDatabase: RemovalExample.lampRecords + [RemovalExample.keypadRecord]
    )

    return DeviceNetwork(modem: modem, catalog: RemovalExample.catalog, snapshot: snapshot, clock: clock)

  }

  @Test(.timeLimit(.minutes(1))) func removingADeviceThatsGoneDeletesItsModemRecordsWithDeclaredDestructiveCommands() async throws {

    let modem = InMemoryModem()
    let sent = Sent()

    await modem.setUnanswering(RemovalExample.lamp)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in await sent.record(operation) }

    let network: DeviceNetwork = await self.network(modem)
    let result: DeviceRemovalResult = try await network.linking.remove(RemovalExample.lamp, forceModemSide: true, observer: LinkingRecorder())

    // Removing with --force-modem-side deletes the modem's two records for the lamp.
    #expect(result.deletedModemRecords.count == 2)
    #expect(await modem.modemRecords == [RemovalExample.keypadRecord])

    let commands: [SerialCommand] = await sent.commands

    #expect(!commands.isEmpty)

    for command in commands {

      #expect(SerialFlowEffects.declaredEffect(of: command.bytes) == .destructive, "\(command.bytes)")

    }

  }

  @Test(.timeLimit(.minutes(1))) func removingADeviceWhoseLinksAnswerSendsOnlyDeclaredCommands() async throws {

    let modem = InMemoryModem()
    let sent = Sent()

    await modem.setEngine(.i2cs, of: RemovalExample.lamp)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in await sent.record(operation) }

    let network: DeviceNetwork = await self.network(modem)

    _ = try await network.linking.remove(RemovalExample.lamp, observer: LinkingRecorder())

    for command in await sent.commands {

      #expect(SerialFlowEffects.declaredEffect(of: command.bytes) != nil, "\(command.bytes)")

    }

  }

}
