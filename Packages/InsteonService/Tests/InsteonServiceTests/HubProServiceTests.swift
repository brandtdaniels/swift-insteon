import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHubPro
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport
import Testing
@testable import InsteonService

/// A Hub Pro is served the way a Hub 2's modem is: the cached devices at once, commands one at a
/// time, events for what changes, and a reconnection of its own when the unit goes away. Time
/// comes from a test clock, and every wait is on a signal.
@Suite(.timeLimit(.minutes(1)))
struct HubProServiceTests {
  let address = InsteonAddress(0x3A, 0x4B, 0x01)
  let clock = TestClock()

  static let describe = HubProUnit.describe(
    device: "3A.4B.01", category: 1, subcategory: 125, firmware: 69,
    commands: [("Beep", []), ("On", ["OnLevel"]), ("Off", []), ("StatusRequest", [])]
  )

  static func listing() -> String {
    #"[{"location":"","name":"(PLM)","device":"AA.BB.CC","deviceType":"Hub Pro"},{"location":"","name":"Example Dimmer","device":"3A.4B.01","deviceType":"Example Dimmer"}]"#
  }

  /// A unit that answers like the one observed, and can lose power.
  actor Unit: HTTPClient {
    let routes = RoutedHTTPClient([
      "GET /settings": answerJSON(HubProUnit.settings),
      "GET /insteon/list": answerJSON(HubProServiceTests.listing()),
      "GET /insteon/status": answerJSON(#"[{"OnLevel":0,"device":"3A.4B.01"}]"#),
      "GET /insteon/describe?device=3A.4B.01": answerJSON(HubProServiceTests.describe),
      "GET /insteon/command?device=3A.4B.01&key=StatusRequest": answerJSON(#"{"LinkDelta":5,"OnLevel":255,"command":"StatusRequest","device":"3A.4B.01","result":"successful"}"#),
      "GET /insteon/command?device=3A.4B.01&key=On&OnLevel=128": answerJSON(HubProUnit.succeeded),
      "GET /insteon/command?device=3A.4B.01&key=Off": answerJSON(HubProUnit.succeeded),
    ])
    private var isOn: Bool

    init(isOn: Bool = true) { self.isOn = isOn }

    func setPower(_ isOn: Bool) { self.isOn = isOn }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
      guard isOn else { throw URLError(.cannotConnectToHost) }
      return try await routes.send(request)
    }
  }

  /// What the service saved of the unit's device on an earlier run.
  private var saved: NetworkSnapshot {
    NetworkSnapshot(
      registry: DeviceRegistrySnapshot(identities: [address: ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)]),
      devices: [address: NetworkDeviceState(level: 77)]
    )
  }

  private func service(_ unit: Unit) -> InsteonService {
    let opener = HubProOpener(host: HubProUnit.host, catalog: nil, httpClient: unit, clock: clock)
    return InsteonService(network: DeviceNetwork.offline(catalog: nil, snapshot: saved, hub: nil), opener: opener, reconnect: .standard, clock: clock, jitter: { 0 }, throughHub: true)
  }

  /// Runs the service with a host that waits until the test is done, with events subscribed first.
  private func running(_ service: InsteonService, _ test: @escaping @Sendable (ServiceEvents) async throws -> Void) async throws {
    let events = await service.events()
    try await withThrowingTaskGroup(of: Void.self) { group in
      let hostStopped = AsyncStream<Void>.makeStream()
      group.addTask { _ = try await service.run { for await _ in hostStopped.0 {} } }
      do { try await test(events) } catch { hostStopped.1.finish(); group.cancelAll(); throw error }
      hostStopped.1.finish()
      try await group.waitForAll()
    }
  }

  private func next(_ events: ServiceEvents, where matches: (ServiceEvent) -> Bool) async throws -> ServiceEvent {
    for try await event in events where matches(event) { return event }
    throw CancellationError()
  }

  @Test func servesTheUnitsDevicesOnceItIsConnected() async throws {
    let unit = Unit()
    let service = service(unit)
    try await running(service) { events in
      _ = try await next(events) { $0 == .modemReconnected }
      let devices = try await service.devices()
      #expect(devices.map(\.address) == [address])
      #expect(devices.first?.canDim == true)
      #expect(devices.first?.value == 0)
      #expect(await service.health().readiness == .ready)
      #expect(await unit.routes.sent == ["GET /settings", "GET /insteon/list", "GET /insteon/describe?device=3A.4B.01", "GET /insteon/status"])
    }
  }

  @Test func readsAStatusAndTurnsADeviceOnAndOff() async throws {
    let unit = Unit()
    let service = service(unit)
    try await running(service) { events in
      _ = try await next(events) { $0 == .modemReconnected }
      let read = try await service.execute(ServiceCommand(address: address, action: .status))
      #expect(read.outcome == .read)
      #expect(read.status?.value == 255)
      let on = try await service.execute(ServiceCommand(address: address, action: .on, levelPercent: 50))
      #expect(on.outcome == .acknowledged)
      let off = try await service.execute(ServiceCommand(address: address, action: .off))
      #expect(off.outcome == .acknowledged)
      #expect(await unit.routes.sent.suffix(3) == [
        "GET /insteon/command?device=3A.4B.01&key=StatusRequest",
        "GET /insteon/command?device=3A.4B.01&key=On&OnLevel=128",
        "GET /insteon/command?device=3A.4B.01&key=Off",
      ])
    }
  }

  @Test func refusesASceneRefreshBecauseAHubProDoesNotGiveOutItsDatabasesAndSendsNothing() async throws {
    let unit = Unit()
    let service = service(unit)
    try await running(service) { events in
      _ = try await next(events) { $0 == .modemReconnected }
      let before = await unit.routes.sent.count
      await #expect(throws: ServiceControlError.databasesUnavailable) {
        try await service.refreshScenes()
      }
      #expect(await unit.routes.sent.count == before)
      // The gate is free again.
      #expect(try await service.execute(ServiceCommand(address: address, action: .status)).outcome == .read)
    }
  }

  @Test func refusesASceneMembershipPlanBecauseAHubProDoesNotGiveOutItsDatabasesAndSendsNothing() async throws {
    let unit = Unit()
    let service = service(unit)
    try await running(service) { events in
      _ = try await next(events) { $0 == .modemReconnected }
      let before = await unit.routes.sent.count
      let change = SceneMembershipChange(scene: 4, additions: [.init(device: address, onLevel: 255, rampRate: 31)], removals: [])!
      await #expect(throws: ServiceControlError.databasesUnavailable) {
        try await service.planSceneMembership(change)
      }
      #expect(await unit.routes.sent.count == before)
    }
  }

  @Test func refusesACommandTheUnitDoesNotListWithoutSendingIt() async throws {
    let unit = Unit()
    await unit.routes.answer("GET /insteon/describe?device=3A.4B.01", with: answerJSON(HubProUnit.describe(device: "3A.4B.01", category: 1, subcategory: 125, firmware: 69, commands: [("StatusRequest", [])])))
    let service = service(unit)
    try await running(service) { events in
      _ = try await next(events) { $0 == .modemReconnected }
      let before = await unit.routes.sent.count
      await #expect(throws: DeviceControlError.self) {
        try await service.execute(ServiceCommand(address: address, action: .on))
      }
      #expect(await unit.routes.sent.count == before)
    }
  }

  @Test func publishesAStatusChangeWhenAnOnLevelChanges() async throws {
    let unit = Unit()
    let service = service(unit)
    try await running(service) { events in
      _ = try await next(events) { $0 == .modemReconnected }
      await clock.waitForSleeper(until: .seconds(5))
      await unit.routes.answer("GET /insteon/status", with: answerJSON(#"[{"OnLevel":200,"device":"3A.4B.01"}]"#))
      clock.advance(by: .seconds(5))
      #expect(try await next(events) { if case .statusChanged = $0 { true } else { false } } == .statusChanged(address))
      #expect(try await service.devices().first?.value == 200)
    }
  }

  @Test func theUnitBeingAwayAtStartIsReportedAsTheHubUnreachableAndRecoversByItself() async throws {
    let unit = Unit(isOn: false)
    let service = service(unit)
    try await running(service) { events in
      await clock.waitForSleeper(until: .seconds(1))
      await #expect(throws: ServiceControlError.modemUnavailable(.hubUnreachable)) {
        try await service.execute(ServiceCommand(address: address, action: .off))
      }
      #expect(await service.health().readiness == .starting)
      await unit.setPower(true)
      clock.advance(by: .seconds(1))
      _ = try await next(events) { $0 == .modemReconnected }
      #expect(try await service.devices().map(\.address) == [address])
    }
  }

  @Test func aFailedPollMakesTheUnitUnavailableThenReconnects() async throws {
    let unit = Unit()
    let service = service(unit)
    try await running(service) { events in
      _ = try await next(events) { $0 == .modemReconnected }
      await clock.waitForSleeper(until: .seconds(5))
      await unit.setPower(false)
      clock.advance(by: .seconds(5))
      #expect(try await next(events) { if case .modemUnavailable = $0 { true } else { false } } == .modemUnavailable(.hubUnreachable))
      #expect(await service.health().readiness == .degraded)
      await clock.waitForSleeper(until: .seconds(6))
      await unit.setPower(true)
      clock.advance(by: .seconds(1))
      _ = try await next(events) { $0 == .modemReconnected }
      #expect(try await service.devices().first?.value == 0)
    }
  }

  @Test func aUnitThatAnswersWithAnErrorStatusIsReportedWithTheStatus() async throws {
    let unit = Unit()
    await unit.routes.answer("GET /settings", with: answerJSON("", status: 503))
    let service = service(unit)
    try await running(service) { events in
      let event = try await next(events) { if case .modemUnavailable = $0 { true } else { false } }
      #expect(event == .modemUnavailable(.hubErrorStatus(503)))
    }
  }
}
