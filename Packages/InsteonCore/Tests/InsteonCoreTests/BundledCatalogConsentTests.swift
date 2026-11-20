import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// What a Set Operating Flags cmd2 `0x0E`, one of the protected bytes, needs granted when the
/// bundled catalog's command set names it for a flag that no guard covers: the effect class the
/// catalog gives it, never a silent send, and never a raw serial send. The identities are
/// numbers only.
struct BundledCatalogConsentTests {

  let clock: TestClock = TestClock()

  static let address = InsteonAddress(0x3A, 0x4B, 0x41)

  /// The identities whose bundled command set names `0x0E` for an unguarded flag.
  static let identities: [(category: UInt8, subcategory: UInt8)] = [(0x00, 0x14), (0x00, 0x17), (0x00, 0x1B)]

  static let message = DirectMessage(to: address, command1: 0x20, command2: 0x0E, data: nil, hasChecksum: false)

  func network(_ identity: (category: UInt8, subcategory: UInt8)) async throws -> (DeviceNetwork, SendAuthorizationTests.Sent) {

    let modem = InMemoryModem()
    let sent = SendAuthorizationTests.Sent()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      await sent.record(operation)

    }

    let reported = ReportedIdentity(category: DeviceCategory(rawValue: identity.category), subcategory: DeviceSubcategory(rawValue: identity.subcategory), firmwareVersion: 0x41)
    let network = DeviceNetwork(
      modem: modem,
      catalog: try DeviceCatalog.bundled(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [Self.address: reported])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    return (network, sent)

  }

  @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2]) func asksForConfigurationConsentAndSendsNothingWithout(_ index: Int) async throws {

    let (network, sent) = try await network(Self.identities[index])

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(Self.message, collectingFor: .seconds(0)) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .needsConsent(.configuration))
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2]) func refusesWhenOnlyOtherEffectsAreGranted(_ index: Int) async throws {

    let (network, sent) = try await network(Self.identities[index])

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(Self.message, collectingFor: .seconds(0), consent: SendConsent(effects: [.actuation, .link], allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .needsConsent(.configuration))
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2]) func sendsWhenConfigurationIsGranted(_ index: Int) async throws {

    let (network, sent) = try await network(Self.identities[index])

    _ = try await network.send(Self.message, collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration])) { (_: ReceivedFrame) -> Void in }

    #expect(await sent.standard == [Command(command1: 0x20, command2: 0x0E)])

  }

  @Test func aRawSerialSendOfTheSameBytesStaysRefusedEvenWhenForced() {

    // 0x62, the device's address, flags 0x0F (standard, max hops), cmd1 0x20, cmd2 0x0E.
    let bytes: [UInt8] = [0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, 0x20, 0x0E]

    for forcing in [false, true] {

      let refusal: SendRefusal? = SerialCommandPolicy.refusal(of: bytes, forcing: forcing)

      #expect(refusal == .protected(.setOperatingFlags0x0E))

    }

  }

}
