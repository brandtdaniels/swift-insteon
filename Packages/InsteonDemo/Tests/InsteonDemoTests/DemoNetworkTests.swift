import InsteonService
import Testing

@testable import InsteonDemo

/// The service the app runs on when no Hub is at hand.
@Suite(.timeLimit(.minutes(1)))
struct DemoNetworkTests {
  @Test func listsEveryDemoDeviceWithAnInventedProductName() async throws {
    let devices = try await DemoNetwork.make().devices()

    #expect(devices.count == DemoNetwork.devices.count)
    #expect(devices.allSatisfy { $0.productName?.hasPrefix("Demo ") == true })
    #expect(devices.allSatisfy { $0.canTurnOnAndOff })
  }

  @Test func aCommandReachesTheDeviceAndTheListReadsItBack() async throws {
    let service = DemoNetwork.make()

    _ = try await service.execute(ServiceCommand(address: DemoNetwork.lamp, action: .on))
    let level = try await service.devices().first { $0.address == DemoNetwork.lamp }?.value

    #expect(level == 0xFF)
  }

  @Test func statusReadsTheLevelTheDeviceHolds() async throws {
    let service = DemoNetwork.make()
    _ = try await service.execute(ServiceCommand(address: DemoNetwork.lamp, action: .on, levelPercent: 50))

    let receipt = try await service.execute(ServiceCommand(address: DemoNetwork.lamp, action: .status))

    #expect(receipt.outcome == .read)
    #expect(receipt.status != nil)
    #expect((0x7F...0x80).contains(try await service.devices().first { $0.address == DemoNetwork.lamp }?.value ?? 0))
  }
}
