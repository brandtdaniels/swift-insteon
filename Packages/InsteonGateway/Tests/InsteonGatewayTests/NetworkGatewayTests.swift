import Foundation
import InsteonCore
import InsteonLinkingTestSupport
import InsteonProtocol
import Testing
@testable import InsteonGateway

@Suite(.timeLimit(.minutes(1)))
struct NetworkGatewayTests {
  private let address = InsteonAddress(0x1A, 0x2B, 0x3C)

  @Test func cachedListingDoesNotSendHardwareRequests() async throws {
    let modem = InMemoryModem()
    let network = network(modem)
    let controller = NetworkGatewayController(network: network)
    let devices = try await controller.devices()
    #expect(devices.count == 1)
    #expect(devices.first?.canDim == true)
    #expect(await modem.linkingSteps.isEmpty)
  }

  @Test func controlsUseCoreAndSaveTheAcknowledgedState() async throws {
    let modem = InMemoryModem()
    let store = MemoryStore()
    let controller = NetworkGatewayController(network: network(modem), store: store)
    let result = try await controller.perform(GatewayCommand(address: address.description, action: .on, levelPercent: 50))
    #expect(result.outcome == .acknowledged)
    #expect(result.status == nil)
    #expect(await modem.levels[address] == 128)
    #expect(await store.saved?.devices[address]?.level == 128)
    let reading = try await controller.perform(GatewayCommand(address: address.description, action: .status))
    #expect(reading.outcome == .read)
    #expect(reading.status == "50%")
  }

  @Test func invalidLevelsAndUnknownDevicesNeverSendCommands() async throws {
    let modem = InMemoryModem()
    let controller = NetworkGatewayController(network: network(modem))
    await #expect(throws: GatewayControlError.invalidLevel) {
      try await controller.perform(GatewayCommand(address: address.description, action: .on, levelPercent: 101))
    }
    await #expect(throws: GatewayControlError.unknownDevice) {
      try await controller.perform(GatewayCommand(address: "11.22.44", action: .off))
    }
    #expect(await modem.linkingSteps.isEmpty)
  }

  @Test func passiveEventsDoNotInventStateReadings() {
    let event = GatewayEvent(.statusChanged(address))
    #expect(event?.kind == "statusChanged")
    #expect(event?.address == address.description)
    #expect(GatewayEvent(.rawMessage([1, 2])) == nil)
  }

  @Test func eventSubscriptionLearnsIdentitiesWithoutInventingDeviceState() async throws {
    let modem = InMemoryModem()
    let network = network(modem)
    let controller = NetworkGatewayController(network: network)
    let events = await controller.events()
    let other = InsteonAddress(0x1A, 0x2B, 0x44)
    await modem.setIdentity(SetButtonPressed(sender: other, role: .responder, category: 1, subcategory: 125, firmwareVersion: 69))
    await modem.broadcastIdentity(of: other)
    var iterator = events.makeAsyncIterator()
    let event = await iterator.next()
    #expect(event?.kind == "setButtonPressed")
    #expect(event?.address == other.description)
    #expect(await network.registry.device(other) != nil)
    #expect(await network.state(of: other)?.level == nil)
    #expect(await network.state(of: other)?.lastSeen == nil)
  }

  private func network(_ modem: InMemoryModem) -> DeviceNetwork {
    DeviceNetwork(modem: modem, catalog: nil, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)])), now: { Date(timeIntervalSince1970: 1_800_000_000) })
  }
}

private actor MemoryStore: NetworkSnapshotStore {
  var saved: NetworkSnapshot?
  func loadNetwork() async throws -> NetworkSnapshot { saved ?? NetworkSnapshot() }
  func saveNetwork(_ snapshot: NetworkSnapshot) async throws { saved = snapshot }
}
