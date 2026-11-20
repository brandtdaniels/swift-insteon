import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonPluginKit
import InsteonService
import Testing
@testable import InsteonServerSupport

/// A deliverer that hands each payload to the test, so the test waits on deliveries and never on time.
struct HandingDeliverer: Deliverer {
  let payloads: AsyncStream<DeliveryPayload>.Continuation
  func deliver(_ payload: DeliveryPayload) async throws { payloads.yield(payload) }
}

/// The reference notifier following the real server, router and service over a scripted modem. Each test waits on
/// deliveries and reports the notifier hands it, which arrive whether or not time passes.
@Suite(.timeLimit(.minutes(2)))
struct NotifierPluginServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  /// A made-up water sensor, identified the way the scratch state names the device.
  static let catalog = DeviceCatalog(profiles: [DeviceProfile(
    model: "9201",
    name: "Example Water Sensor",
    identities: [DeviceIdentity(category: 1, subcategory: 125)],
    groups: [DeviceProfile.Group(number: 2, name: "Wet", role: .controller)],
    capabilities: [.groupEvents([DeviceCapability.GroupEvent(group: 2, command1: 0x11, event: "wet")])]
  )])

  private func connected(_ directory: URL) async throws -> (server: RunningServer, link: HubLink) {
    let link = HubLink()
    let server = try await start(directory, openModem: opener(ScriptedHubOpener([.connect(link)], catalog: Self.catalog, clock: SteppingClock())))
    _ = await server.code("modem_connected")
    return (server, link)
  }

  private func rule(named name: String) -> String {
    #"{"name":""# + name + #"","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"cooldownSeconds":0,"includeDetail":true}"#
  }

  /// A notifier task, and the deliveries and reports it hands the test.
  private struct RunningNotifier {
    let task: Task<Void, any Error>
    var deliveries: AsyncStream<DeliveryPayload>.Iterator
    var reports: AsyncStream<NotifierReport>.Iterator

    init(server: RunningServer, token: String, state: URL, includesDetail: Bool = false) {
      let (payloads, handed) = AsyncStream<DeliveryPayload>.makeStream()
      let (reported, report) = AsyncStream<NotifierReport>.makeStream()
      let notifier = Notifier(
        source: ServiceEventSource(service: server.plugin(token: token)),
        deliverer: HandingDeliverer(payloads: handed),
        state: FileNotifierState(url: state),
        includesDetail: includesDetail,
        report: { report.yield($0) }
      )
      task = Task { try await notifier.run() }
      deliveries = payloads.makeAsyncIterator()
      reports = reported.makeAsyncIterator()
    }

    /// Returns once the service has subscribed the notifier, so a notification fired afterward reaches it.
    mutating func connected() async {
      while let report = await reports.next(), report != .connected {}
    }

    func stop() async -> (any Error)? {
      task.cancel()
      if case let .failure(error) = await task.result { return error }
      return nil
    }
  }

  private func fire(_ link: HubLink) async {
    await link.modem.broadcastGroupCommand(from: device, group: 2, command1: 0x11)
  }

  @Test func aRuleFiresAndTheNotifierDeliversOneContentFreeNotification() async throws {
    let directory = try scratch()
    let (server, link) = try await connected(directory)
    let token = try await server.token(named: "Notifier", scope: "read", password: gatewayPassword)
    _ = try await server.request("/api/v1/notification-rules/basement-leak", method: "PUT", body: rule(named: "Basement leak"), password: gatewayPassword)
    var notifier = RunningNotifier(server: server, token: token, state: directory.appendingPathComponent("notifier.json"))
    await notifier.connected()
    await fire(link)
    let first = try #require(await notifier.deliveries.next())
    #expect(first.ruleName == "Basement leak" && first.address == nil && first.event == nil)
    #expect(!first.firedAt.isEmpty)
    #expect(first.line == first.firedAt + "\tBasement leak")
    _ = await notifier.stop()
    await server.stop()
  }

  @Test func detailReachesTheDelivererOnlyWhenTheNotifierIsToldToIncludeIt() async throws {
    let directory = try scratch()
    let (server, link) = try await connected(directory)
    let token = try await server.token(named: "Notifier", scope: "read", password: gatewayPassword)
    _ = try await server.request("/api/v1/notification-rules/basement-leak", method: "PUT", body: rule(named: "Basement leak"), password: gatewayPassword)
    var notifier = RunningNotifier(server: server, token: token, state: directory.appendingPathComponent("notifier.json"), includesDetail: true)
    await notifier.connected()
    await fire(link)
    let delivered = try #require(await notifier.deliveries.next())
    #expect(delivered.address == "1A.2B.3C" && delivered.event == "wet")
    _ = await notifier.stop()
    await server.stop()
  }

  @Test func aRestartedNotifierResumesFromItsStateFileAndDeliversNothingTwice() async throws {
    let directory = try scratch()
    let state = directory.appendingPathComponent("notifier.json")
    let (server, link) = try await connected(directory)
    let token = try await server.token(named: "Notifier", scope: "read", password: gatewayPassword)
    _ = try await server.request("/api/v1/notification-rules/leak", method: "PUT", body: rule(named: "First"), password: gatewayPassword)

    var running = RunningNotifier(server: server, token: token, state: state)
    await running.connected()
    await fire(link)
    #expect(try #require(await running.deliveries.next()).ruleName == "First")
    // The id is recorded after the delivery; the stopped notifier ends having read it.
    _ = await running.stop()
    let recorded = try #require(try FileNotifierState(url: state).lastEventID())
    #expect(try FileManager.default.attributesOfItem(atPath: state.path)[.posixPermissions] as? Int == 0o600)

    // A notification the notifier wasn't running for.
    _ = try await server.request("/api/v1/notification-rules/leak", method: "PUT", body: rule(named: "Second"), password: gatewayPassword)
    await fire(link)

    var restarted = RunningNotifier(server: server, token: token, state: state)
    await restarted.connected()
    // Replays come first. If First were delivered again it would arrive before Second.
    #expect(try #require(await restarted.deliveries.next()).ruleName == "Second")
    _ = try await server.request("/api/v1/notification-rules/leak", method: "PUT", body: rule(named: "Third"), password: gatewayPassword)
    await fire(link)
    #expect(try #require(await restarted.deliveries.next()).ruleName == "Third")
    #expect(try FileNotifierState(url: state).lastEventID() != recorded)
    _ = await restarted.stop()
    await server.stop()
  }

  @Test func aStateFromAnotherRunIsAGapThatIsReportedAndLeavesTheNotifierFollowingTheStream() async throws {
    let directory = try scratch()
    let state = directory.appendingPathComponent("notifier.json")
    try FileNotifierState(url: state).record(lastEventID: "feedbeef-3")
    let (server, link) = try await connected(directory)
    let token = try await server.token(named: "Notifier", scope: "read", password: gatewayPassword)
    _ = try await server.request("/api/v1/notification-rules/leak", method: "PUT", body: rule(named: "Leak"), password: gatewayPassword)
    var notifier = RunningNotifier(server: server, token: token, state: state)
    await notifier.connected()
    #expect(await notifier.reports.next() == .gap(rules: 1))
    // The notifier's place is in the current run, and it delivers what happens from there.
    await fire(link)
    #expect(try #require(await notifier.deliveries.next()).ruleName == "Leak")
    let place = try #require(try FileNotifierState(url: state).lastEventID())
    #expect(!place.hasPrefix("feedbeef"))
    _ = await notifier.stop()
    await server.stop()
  }

  @Test func aRevokedTokenEndsTheNotifierWithAnAuthorizationFailureAndNothingIsDelivered() async throws {
    let directory = try scratch()
    let (server, _) = try await connected(directory)
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Notifier","scope":"read"}"#, password: gatewayPassword)
    let token = try #require((created.json["pairing"] as? [String: Any])?["credential"] as? String)
    let id = try #require((created.json["client"] as? [String: Any])?["id"] as? String)
    _ = try await server.request("/api/v1/clients/" + id, method: "DELETE", password: gatewayPassword)
    let notifier = RunningNotifier(server: server, token: token, state: directory.appendingPathComponent("notifier.json"))
    let error = await notifier.task.result
    guard case let .failure(failure) = error, case let .unauthorized(status, _) = failure as? PluginError else {
      Issue.record("expected an authorization failure, got \(error)")
      await server.stop()
      return
    }
    #expect(status == 401)
    await server.stop()
  }

  @Test func theTokenIsNeverInAReportAnErrorOrTheServersLog() async throws {
    let directory = try scratch()
    let (server, link) = try await connected(directory)
    let token = try await server.token(named: "Notifier", scope: "read", password: gatewayPassword)
    let secret = try #require(token.split(separator: ".").last.map(String.init))
    _ = try await server.request("/api/v1/notification-rules/leak", method: "PUT", body: rule(named: "Leak"), password: gatewayPassword)
    var notifier = RunningNotifier(server: server, token: token, state: directory.appendingPathComponent("notifier.json"))
    await notifier.connected()
    await fire(link)
    let delivered = try #require(await notifier.deliveries.next())
    #expect(!String(describing: delivered).contains(secret))
    #expect(!String(describing: server.plugin(token: token)).contains(secret))
    _ = await notifier.stop()
    let log = server.capture.records.map(\.rendered).joined(separator: "\n")
    #expect(!log.contains(secret))
    await server.stop()
  }
}
