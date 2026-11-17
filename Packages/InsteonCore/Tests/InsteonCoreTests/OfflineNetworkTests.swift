import Foundation
import InsteonModem
import InsteonProtocol
import Testing
@testable import InsteonCore

@Suite(.timeLimit(.minutes(1)))
struct OfflineNetworkTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  var snapshot: NetworkSnapshot {

    NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [lamp: ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)]),
      devices: [lamp: NetworkDeviceState(level: 128, lastSeen: Date(timeIntervalSince1970: 1_800_000_000))]
    )

  }

  @Test func anOfflineNetworkKeepsWhatTheSnapshotKnows() async {

    let network = DeviceNetwork.offline(catalog: nil, snapshot: snapshot, hub: nil)

    #expect(await network.snapshot() == snapshot)
    #expect(await network.registry.device(lamp) != nil)
    #expect(await network.state(of: lamp)?.level == 128)

  }

  @Test func anOfflineNetworkNeverReachesAModem() async {

    let network = DeviceNetwork.offline(catalog: nil, snapshot: snapshot, hub: nil)

    await #expect(throws: ModemError.connectionClosed) { try await network.modemInfo() }
    await #expect(throws: ModemError.connectionClosed) { try await network.modemDatabase() }
    await #expect(throws: ModemError.connectionClosed) { try await network.identify(InsteonAddress(0x11, 0x22, 0x33)) }

    // What it tried doesn't change what it knows.
    #expect(await network.snapshot() == snapshot)

  }

}
