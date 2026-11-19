import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonService
import Testing
@testable import InsteonServerSupport

/// Notification rules over the real runner, router, service, files and a scripted modem. Nothing waits on
/// time: each test waits on frames the stream delivers, and every wait ends in a frame whether or not the
/// rule fired, because a report no rule names always follows.
@Suite(.timeLimit(.minutes(2)))
struct NotificationServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)
  let stranger = InsteonAddress(0x1A, 0x2B, 0x44)
  static let rule = #"{"name":"Basement leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"cooldownSeconds":300}"#

  /// A made-up water sensor, identified the way the scratch state names the device.
  static let catalog = DeviceCatalog(profiles: [DeviceProfile(
    model: "9201",
    name: "Example Water Sensor",
    identities: [DeviceIdentity(category: 1, subcategory: 125)],
    groups: [DeviceProfile.Group(number: 2, name: "Wet", role: .controller)],
    capabilities: [.groupEvents([DeviceCapability.GroupEvent(group: 2, command1: 0x11, event: "wet")])]
  )])

  private func connected(_ directory: URL? = nil) async throws -> (server: RunningServer, link: HubLink) {
    let link = HubLink()
    let server = try await start(try directory ?? scratch(), openModem: opener(ScriptedHubOpener([.connect(link)], catalog: Self.catalog, clock: SteppingClock())))
    _ = await server.code("modem_connected")
    return (server, link)
  }

  private func readClient(_ server: RunningServer) async throws -> String {
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Notifier","scope":"read"}"#, password: gatewayPassword)
    return try #require((created.json["pairing"] as? [String: Any])?["credential"] as? String)
  }

  private func stream(_ server: RunningServer, bearer: String, lastEventID: String? = nil) async -> EventStreamReader {
    let reader = EventStreamReader(port: server.port, password: gatewayPassword, bearer: bearer, lastEventID: lastEventID)
    var ready = reader.ready.makeAsyncIterator()
    _ = await ready.next()
    return reader
  }

  /// Frames up to and including the next report of `stranger`, which no rule names.
  private func settle(_ frames: inout AsyncStream<EventStreamReader.Frame>.Iterator, _ link: HubLink) async throws -> [[String: Any]] {
    await link.modem.broadcastGroupCommand(from: stranger, group: 9, command1: 0x11)
    var seen: [[String: Any]] = []
    while let frame = await frames.next() {
      seen.append(frame.json)
      if frame.json["kind"] as? String == "groupCommand", frame.json["address"] as? String == stranger.description { return seen }
    }
    return seen
  }

  @Test func aRuleCreatedThroughTheApiFiresAndAReadClientReceivesOneContentFreeNotification() async throws {
    let (server, link) = try await connected()
    let token = try await readClient(server)
    let created = try await server.request("/api/v1/notification-rules/basement-leak", method: "PUT", body: Self.rule, password: gatewayPassword)
    #expect(created.status == 200)
    let reader = await stream(server, bearer: token)
    var frames = reader.frames.makeAsyncIterator()
    await link.modem.broadcastGroupCommand(from: device, group: 2, command1: 0x11)
    let seen = try await settle(&frames, link)
    let notifications = seen.filter { $0["kind"] as? String == "notification" }
    #expect(notifications.count == 1)
    let note = try #require(notifications.first)
    #expect(Set(note.keys) == ["version", "runId", "sequence", "kind", "ruleId", "ruleName", "address", "firedAt"])
    #expect(note["ruleId"] as? String == "basement-leak" && note["ruleName"] as? String == "Basement leak" && note["address"] as? String == "1A.2B.3C")
    reader.close()
    await server.stop()
  }

  @Test func aReportInsideTheCooldownAddsNoSecondNotificationAndAResumeReplaysTheFirstOnce() async throws {
    let (server, link) = try await connected()
    let token = try await readClient(server)
    _ = try await server.request("/api/v1/notification-rules/basement-leak", method: "PUT", body: Self.rule, password: gatewayPassword)
    let first = await stream(server, bearer: token)
    var frames = first.frames.makeAsyncIterator()
    await link.modem.broadcastGroupCommand(from: device, group: 2, command1: 0x11)
    await link.modem.broadcastGroupCommand(from: device, group: 2, command1: 0x11)
    let seen = try await settle(&frames, link)
    #expect(seen.filter { $0["kind"] as? String == "notification" }.count == 1)
    // A client that saw only the first report resumes from it and is given the notification, once.
    let report = try #require(seen.first { $0["kind"] as? String == "groupCommand" })
    let run = try #require(report["runId"] as? String)
    first.close()
    let resumed = await stream(server, bearer: token, lastEventID: "\(run)-\(report["sequence"] as! Int)")
    var replay = resumed.frames.makeAsyncIterator()
    let missed = try await settle(&replay, link)
    #expect(missed.filter { $0["kind"] as? String == "notification" }.count == 1)
    #expect(!missed.contains { $0["kind"] as? String == "gap" })
    resumed.close()
    await server.stop()
  }

  @Test func rulesSurviveARestartInAPrivateFileBesideTheStateFile() async throws {
    let directory = try scratch()
    let (first, _) = try await connected(directory)
    _ = try await first.request("/api/v1/notification-rules/basement-leak", method: "PUT", body: Self.rule, password: gatewayPassword)
    await first.stop()

    let url = FileNotificationRulePersistence.url(besideState: directory.appendingPathComponent("state.json").path)
    #expect(url.lastPathComponent == "state-notification-rules.json")
    let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)

    let (second, _) = try await connected(directory)
    let listed = try await second.request("/api/v1/notification-rules", password: gatewayPassword)
    let rules = try #require(listed.json["rules"] as? [[String: Any]])
    #expect(rules.map { $0["id"] as? String } == ["basement-leak"])
    await second.stop()
  }

  @Test func aRuleForADeviceTheServiceDoesNotKnowIsRefusedWithATypedError() async throws {
    let (server, _) = try await connected()
    let body = #"{"name":"Nobody","trigger":{"kind":"event","event":"wet","device":"77.77.77"}}"#
    let refused = try await server.request("/api/v1/notification-rules/nobody", method: "PUT", body: body, password: gatewayPassword)
    #expect(refused.status == 404)
    #expect(refused.json["code"] as? String == "unknownDevice")
    let badID = try await server.request("/api/v1/notification-rules/has%20space", method: "PUT", body: Self.rule, password: gatewayPassword)
    #expect(badID.json["code"] as? String == "invalidNotificationRule")
    await server.stop()
  }

  @Test func aRulesFileThatCannotBeReadStopsTheServerBeforeItListens() async throws {
    let directory = try scratch()
    try Data("garbage".utf8).write(to: FileNotificationRulePersistence.url(besideState: directory.appendingPathComponent("state.json").path))
    let environment = ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"]
    do {
      try await ServerRunner.run(arguments: ["--state", directory.appendingPathComponent("state.json").path, "--hub", "192.168.1.20"], environment: environment, openModem: opener(ScriptedHubOpener([])))
      Issue.record("the server should not start")
    } catch {
      #expect(ServerFailure(error).code == .notificationRulesFileUnusable)
    }
  }
}
