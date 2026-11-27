import Foundation
import InsteonCore
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import Testing
@testable import InsteonService

/// The service's tuning: its standard values, what it accepts, and where it is used and shown.
@Suite(.timeLimit(.minutes(1)))
struct ServiceTuningTests {
  @Test func theStandardScenesValuesAreFiveFifteenAndSixtySeconds() throws {
    let scenes = ServiceTuning.standard.scenes
    #expect(scenes.echoWait == .seconds(5))
    #expect(scenes.cleanupQuietPeriod == .seconds(15))
    #expect(scenes.cleanupCap == .seconds(60))
    #expect(try ServiceTuning.standard.validated() == .standard)
  }

  @Test func roundTripsThroughJSON() throws {
    var tuning = ServiceTuning.standard
    tuning.scenes.cleanupCap = .seconds(90)
    let decoded = try JSONDecoder().decode(ServiceTuning.self, from: JSONEncoder().encode(tuning))
    #expect(decoded == tuning)
  }

  @Test(arguments: [
    (Duration.zero, Duration.seconds(15), Duration.seconds(60), ServiceTuningError.Field.scenesEchoWait),
    (.seconds(-1), .seconds(15), .seconds(60), ServiceTuningError.Field.scenesEchoWait),
    (.seconds(61), .seconds(15), .seconds(60), ServiceTuningError.Field.scenesEchoWait),
    (.seconds(5), .zero, .seconds(60), ServiceTuningError.Field.scenesCleanupQuiet),
    (.seconds(5), .milliseconds(2_149), .seconds(60), ServiceTuningError.Field.scenesCleanupQuiet),
    (.seconds(5), .seconds(61), .seconds(60), ServiceTuningError.Field.scenesCleanupQuiet),
    (.seconds(5), .seconds(15), .zero, ServiceTuningError.Field.scenesCleanupCap),
    (.seconds(5), .seconds(15), .seconds(301), ServiceTuningError.Field.scenesCleanupCap)
  ])
  func refusesAValueOutOfRangeAndNamesTheField(_ echo: Duration, _ quiet: Duration, _ cap: Duration, _ field: ServiceTuningError.Field) {
    let tuning = ServiceTuning(scenes: .init(echoWait: echo, cleanupQuietPeriod: quiet, cleanupCap: cap))
    #expect(throws: ServiceTuningError.invalid(field: field)) { try tuning.validated() }
  }

  // The Insteon Developer's Guide gives 2.150 seconds to the first cleanup, so a quiet period may only be longer.
  @Test func aQuietPeriodMayNotBeShorterThanTheGuidesFirstCleanup() throws {
    #expect(ServiceTuning.minimumCleanupQuietPeriod == .milliseconds(2_150))
    let tuning = ServiceTuning(scenes: .init(echoWait: .seconds(1), cleanupQuietPeriod: .milliseconds(2_150), cleanupCap: .seconds(300)))
    #expect(try tuning.validated() == tuning)
  }

  @Test func eachFieldHasTheNameHealthAndTheFlagsUse() {
    #expect(ServiceTuningError.Field.scenesEchoWait.name == "scenes.echoWaitMs")
    #expect(ServiceTuningError.Field.scenesCleanupQuiet.name == "scenes.cleanupQuietMs")
    #expect(ServiceTuningError.Field.scenesCleanupCap.name == "scenes.cleanupCapMs")
  }

  @Test func listsEveryValueWithItsSourceDefaultingToDefault() {
    var tuning = ServiceTuning.standard
    tuning.scenes.cleanupCap = .seconds(90)
    let entries = tuning.entries(sources: ["scenes.cleanupCapMs": .flag, "scenes.echoWaitMs": .environment])

    #expect(entries == [
      TuningEntry(name: "scenes.echoWaitMs", milliseconds: 5_000, source: .environment),
      TuningEntry(name: "scenes.cleanupQuietMs", milliseconds: 15_000, source: .default),
      TuningEntry(name: "scenes.cleanupCapMs", milliseconds: 90_000, source: .flag)
    ])
  }

  // MARK: Where it is used and shown

  @Test func runsASceneWithTheWaitTheTuningGives() async throws {
    let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
    let modem = InMemoryModem()
    await modem.setModemRecords([AllLinkRecord(flags: [.inUse, .controller], group: 3, address: lamp, data1: 0, data2: 0, data3: 0)])
    await modem.setDatabase([0x0FFF: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 3, address: InsteonAddress(0x11, 0x22, 0x33), data1: 0xFF, data2: 0x1F, data3: 0x01)], of: lamp)
    var tuning = ServiceTuning.standard
    tuning.scenes = .init(echoWait: .seconds(7), cleanupQuietPeriod: .seconds(11), cleanupCap: .seconds(90))
    let identity = ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)
    let network = DeviceNetwork(modem: modem, catalog: nil, snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [lamp: identity])))
    let service = InsteonService(network: network, tuning: tuning)
    _ = try await service.refreshScenes()

    _ = try await service.runScene(SceneCommand(number: 3, action: .on))

    #expect(await modem.groupCommands.map(\.wait) == [AllLinkCleanupWait(echo: .seconds(7), quietPeriod: .seconds(11), cap: .seconds(90))])
  }

  @Test func reportsTheEffectiveValuesAndTheirSourcesInHealth() async {
    var tuning = ServiceTuning.standard
    tuning.scenes.echoWait = .seconds(8)
    let network = DeviceNetwork(modem: InMemoryModem(), catalog: nil)
    let service = InsteonService(network: network, tuning: tuning, tuningSources: ["scenes.echoWaitMs": .flag])

    let health = await service.health()

    #expect(health.tuning.first == TuningEntry(name: "scenes.echoWaitMs", milliseconds: 8_000, source: .flag))
    #expect(health.tuning.count == 3)
    #expect(health.tuning.dropFirst().allSatisfy { $0.source == .default })
  }
}
