import InsteonCore
import InsteonProtocol
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

/// The scenes the app lists and runs on the demo network.
@Suite(.timeLimit(.minutes(1)))
struct DemoNetworkSceneTests {
  @Test func readingTheDatabasesListsAWritableSceneWithItsMembersAndTheirStoredData() async throws {
    let listing = try await DemoNetwork.make().refreshScenes()

    let scene = try #require(listing.scenes.first { $0.number == 20 })
    #expect(scene.isWritable)
    #expect(Set(scene.members.map(\.address)) == [DemoNetwork.lamp, DemoNetwork.ceiling])
    #expect(scene.members.allSatisfy { $0.data == [0xFF, 0x1F, 0x01] })
    #expect(listing.isWhole)
  }

  @Test func everyDemoSceneIsWritableAndHasMembers() async throws {
    let listing = try await DemoNetwork.make().refreshScenes()

    #expect(listing.scenes.map { AllLinkGroupNumber(rawValue: $0.number) } == DemoNetwork.scenes.map(\.group))
    #expect(listing.scenes.allSatisfy { $0.isWritable && !$0.members.isEmpty })
  }

  @Test func runningTheSceneOnTurnsItsMembersOnAndOffTurnsThemOff() async throws {
    let service = DemoNetwork.make()
    _ = try await service.refreshScenes()

    // A run reads no member afterward, so each member is asked what level it holds.
    func level(_ address: InsteonAddress) async throws -> UInt8? {
      try await service.execute(ServiceCommand(address: address, action: .status)).status?.value
    }

    let on = try await service.runScene(SceneCommand(number: 20, action: .on))

    #expect(on.isComplete)
    #expect(Set(on.acknowledged) == [DemoNetwork.lamp, DemoNetwork.ceiling])
    #expect(try await level(DemoNetwork.lamp) == 0xFF)
    #expect(try await level(DemoNetwork.ceiling) == 0xFF)
    #expect(try await level(DemoNetwork.outlet) == 0x00)

    _ = try await service.runScene(SceneCommand(number: 20, action: .off))
    #expect(try await level(DemoNetwork.lamp) == 0x00)
    #expect(try await level(DemoNetwork.ceiling) == 0x00)
  }

  @Test func aSceneIsNotRunnableBeforeTheDatabasesAreRead() async throws {
    await #expect(throws: ServiceControlError.unknownScene) { try await DemoNetwork.make().runScene(SceneCommand(number: 20, action: .on)) }
  }
}
