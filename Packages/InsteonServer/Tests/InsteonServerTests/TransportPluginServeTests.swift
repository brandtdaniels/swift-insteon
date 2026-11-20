import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHubClient
import InsteonLoopbackTransport
import InsteonPluginKit
import Testing
@testable import InsteonServerSupport

/// The reference transport in front of the real server, router and service over the scripted modem. A remote client reaches
/// the service through the transport's own port, and every contract behavior is the one the LAN has. Nothing waits on time:
/// each test waits on frames the stream delivers and on tasks that end.
@Suite(.timeLimit(.minutes(2)))
struct TransportPluginServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  private func connected() async throws -> (server: RunningServer, link: HubLink, adminToken: String) {
    let link = HubLink()
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.connect(link)])))
    _ = await server.code("modem_connected")
    return (server, link, try await server.token(named: "Transport", scope: "admin", password: gatewayPassword))
  }

  private func stream(port: Int, bearer: String, lastEventID: String? = nil) async -> EventStreamReader {
    let reader = EventStreamReader(port: port, password: gatewayPassword, bearer: bearer, lastEventID: lastEventID)
    var ready = reader.ready.makeAsyncIterator()
    _ = await ready.next()
    return reader
  }

  private func commands(_ count: Int, on server: RunningServer) async throws {
    for index in 0..<count {
      let result = try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: index.isMultiple(of: 2) ? #"{"action":"on"}"# : #"{"action":"off"}"#, password: gatewayPassword)
      #expect(result.status == 200)
    }
  }

  // MARK: Registration

  @Test func theTransportRegistersItsRouteAndEveryPairingAfterwardListsIt() async throws {
    let (server, _, admin) = try await connected()
    let transport = try await RunningTransport.start(for: server, token: admin)
    let listed = try await server.request("/api/v1/routes", password: gatewayPassword)
    let routes = try #require(listed.json["routes"] as? [[String: Any]])
    #expect(routes.count == 1 && routes[0]["kind"] as? String == "loopback" && routes[0]["ticket"] as? String == "127.0.0.1:\(transport.port)")

    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Phone","scope":"control"}"#, password: gatewayPassword)
    let pairing = try #require(created.json["pairing"] as? [String: Any])
    let documented = try #require(pairing["routes"] as? [[String: Any]])
    #expect(documented.map { $0["kind"] as? String } == ["lan", "loopback"])
    try #require(documented.count == 2)
    #expect(documented[1]["ticket"] as? String == "127.0.0.1:\(transport.port)")
    await transport.stop()
    await server.stop()
  }

  @Test func aTokenWithoutTheAdminScopeCannotRegisterAndLeavesNothingListening() async throws {
    let (server, _, _) = try await connected()
    let control = try await server.token(named: "Not admin", scope: "control", password: gatewayPassword)
    do {
      _ = try await RunningTransport.start(for: server, token: control)
      Issue.record("the transport should not start")
    } catch {
      #expect(error as? PluginError == .unauthorized(status: 403, code: "forbidden"))
    }
    let listed = try await server.request("/api/v1/routes", password: gatewayPassword)
    #expect((listed.json["routes"] as? [Any])?.isEmpty == true)
    await server.stop()
  }

  // MARK: The contract through the transport

  @Test func authenticationAndScopesAnswerThroughTheTransportAsTheyDoOnTheLAN() async throws {
    let (server, _, admin) = try await connected()
    let transport = try await RunningTransport.start(for: server, token: admin)
    let remote = server.reached(through: transport.port)
    let reader = try await server.token(named: "Display", scope: "read", password: gatewayPassword)
    let controller = try await server.token(named: "Phone", scope: "control", password: gatewayPassword)
    let command = #"{"action":"on"}"#

    func answers(_ via: RunningServer) async throws -> [String] {
      var seen: [String] = []
      for (path, method, body, bearer) in [
        ("/api/v1/health", "GET", nil, controller), ("/api/v1/devices", "GET", nil, reader),
        ("/api/v1/devices/1A.2B.3C/commands", "POST", command, reader), ("/api/v1/devices/1A.2B.3C/commands", "POST", command, controller),
        ("/api/v1/devices", "GET", nil, "0000000000000000.wrong"), ("/api/v1/clients", "GET", nil, controller)
      ] as [(String, String, String?, String)] {
        let result = try await via.request(path, method: method, body: body, password: gatewayPassword, bearer: bearer)
        seen.append("\(result.status) \(result.json["code"] as? String ?? "-") \(result.json["sent"] as? Bool ?? false)")
      }
      let password = try await via.request("/api/v1/health", password: gatewayPassword)
      seen.append("\(password.status)")
      return seen
    }
    let lan = try await answers(server)
    let remoteAnswers = try await answers(remote)
    #expect(remoteAnswers == lan)
    #expect(lan == ["200 - false", "200 - false", "403 forbidden false", "200 - false", "401 authenticationFailed false", "403 forbidden false", "200"])
    await transport.stop()
    await server.stop()
  }

  @Test func aRepeatedKeyedCommandThroughTheTransportReturnsTheRecordedAnswerAndSendsNothing() async throws {
    let (server, link, admin) = try await connected()
    let transport = try await RunningTransport.start(for: server, token: admin)
    let remote = server.reached(through: transport.port)
    let key = ["Idempotency-Key": "remote-0001"]
    let first = try await remote.exchange("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, headers: key, password: gatewayPassword)
    let second = try await remote.exchange("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, headers: key, password: gatewayPassword)
    #expect(first.status == 200 && first.headers["idempotent-replay"] == nil)
    #expect(second.status == 200 && second.headers["idempotent-replay"] == "true")
    #expect(NSDictionary(dictionary: second.json).isEqual(to: first.json))
    #expect(await link.modem.requestCounts[device] == 1)
    await transport.stop()
    await server.stop()
  }

  @Test func anEventStreamThroughTheTransportResumesFromItsLastIdWithNoGap() async throws {
    let (server, _, admin) = try await connected()
    let transport = try await RunningTransport.start(for: server, token: admin)
    let control = try await server.token(named: "Phone", scope: "control", password: gatewayPassword)
    let first = await stream(port: transport.port, bearer: control)
    var seen = first.frames.makeAsyncIterator()
    try await commands(1, on: server)
    let one = try #require(await seen.next())
    #expect(one.json["kind"] as? String == "commandCompleted")
    first.close()
    try await commands(2, on: server)
    let second = await stream(port: transport.port, bearer: control, lastEventID: one.id)
    var resumed = second.frames.makeAsyncIterator()
    let two = try #require(await resumed.next())
    let three = try #require(await resumed.next())
    let base = one.json["sequence"] as! Int
    #expect(two.json["sequence"] as? Int == base + 1 && three.json["sequence"] as? Int == base + 2)
    #expect(two.json["kind"] as? String == "commandCompleted" && three.json["kind"] as? String == "commandCompleted")
    second.close()
    await transport.stop()
    await server.stop()
  }

  @Test func aStreamFromAnotherRunGetsAGapThroughTheTransport() async throws {
    let (server, _, admin) = try await connected()
    let transport = try await RunningTransport.start(for: server, token: admin)
    let reader = await stream(port: transport.port, bearer: try await server.token(named: "Phone", scope: "control", password: gatewayPassword), lastEventID: "feedbeef-3")
    var frames = reader.frames.makeAsyncIterator()
    let gap = try #require(await frames.next())
    #expect(gap.json["kind"] as? String == "gap" && gap.json["reason"] as? String == "otherRun")
    reader.close()
    await transport.stop()
    await server.stop()
  }

  @Test func aStreamThatStaysOpenKeepsReceivingLiveEventsThroughTheTransport() async throws {
    let (server, _, admin) = try await connected()
    let transport = try await RunningTransport.start(for: server, token: admin)
    let reader = await stream(port: transport.port, bearer: try await server.token(named: "Phone", scope: "control", password: gatewayPassword))
    var frames = reader.frames.makeAsyncIterator()
    for round in 0..<3 {
      try await commands(1, on: server)
      let frame = try #require(await frames.next())
      #expect(frame.json["kind"] as? String == "commandCompleted", "round \(round)")
    }
    reader.close()
    await transport.stop()
    await server.stop()
  }

  // MARK: Stopping and dropping

  @Test func whenTheTransportStopsItRemovesItsRouteAndTheServiceIsUnaffected() async throws {
    let (server, _, admin) = try await connected()
    let transport = try await RunningTransport.start(for: server, token: admin)
    let port = transport.port
    await transport.stop()

    let listed = try await server.request("/api/v1/routes", password: gatewayPassword)
    #expect((listed.json["routes"] as? [Any])?.isEmpty == true)
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Phone","scope":"control"}"#, password: gatewayPassword)
    #expect(((created.json["pairing"] as? [String: Any])?["routes"] as? [[String: Any]])?.count == 1)
    // LAN clients keep working, and nothing listens on the transport's port any more.
    #expect(try await server.request("/api/v1/health", password: gatewayPassword).status == 200)
    try await commands(1, on: server)
    await #expect(throws: (any Error).self) { try await server.reached(through: port).request("/api/v1/health", password: gatewayPassword) }
    await server.stop()
  }

  @Test func aTransportThatRegistersAgainReplacesItsOwnRouteInsteadOfAddingAnother() async throws {
    let (server, _, admin) = try await connected()
    // A stale route of the same kind, as a transport that died without removing it leaves, is replaced.
    try await RouteRegistrar(service: server.plugin(token: admin)).register(kind: "loopback", ticket: "127.0.0.1:1")
    let transport = try await RunningTransport.start(for: server, token: admin)
    let listed = try await server.request("/api/v1/routes", password: gatewayPassword)
    let routes = try #require(listed.json["routes"] as? [[String: Any]])
    #expect(routes.count == 1 && routes[0]["ticket"] as? String == "127.0.0.1:\(transport.port)")
    await transport.stop()
    await server.stop()
  }

  /// A forwarder whose service is gone closes each connection it can't pass on, and keeps accepting.
  @Test func aForwarderWhoseServiceIsGoneClosesEachConnectionAndKeepsAccepting() async throws {
    let forwarder = LoopbackForwarder(upstreamPort: try FreePort.unused())
    let (ports, listening) = AsyncStream<Int>.makeStream()
    let task = Task { try await forwarder.run { listening.yield($0) } }
    let ended = Task { _ = await task.result; listening.finish() }
    var iterator = ports.makeAsyncIterator()
    let port = try #require(await iterator.next())
    ended.cancel()
    let unreachable = ConnectionProbe(port: port)
    for _ in 0..<2 {
      await #expect(throws: (any Error).self) { try await unreachable.get("/api/v1/health") }
    }
    task.cancel()
    _ = await task.result
  }

  @Test func aDroppedConnectionResumesWithTheLastIdOnAnotherTransportWithNoGap() async throws {
    let (server, _, admin) = try await connected()
    let control = try await server.token(named: "Phone", scope: "control", password: gatewayPassword)
    let first = try await RunningTransport.start(for: server, token: admin)
    let reader = await stream(port: first.port, bearer: control)
    var frames = reader.frames.makeAsyncIterator()
    try await commands(1, on: server)
    let one = try #require(await frames.next())

    // The transport goes away with the stream open: the client's connection ends.
    await first.stop()
    #expect(await frames.next() == nil)
    reader.close()
    try await commands(2, on: server)

    let second = try await RunningTransport.start(for: server, token: admin)
    let resumed = await stream(port: second.port, bearer: control, lastEventID: one.id)
    var replay = resumed.frames.makeAsyncIterator()
    let two = try #require(await replay.next())
    let three = try #require(await replay.next())
    #expect(two.json["kind"] as? String == "commandCompleted" && three.json["kind"] as? String == "commandCompleted")
    #expect(two.json["sequence"] as? Int == (one.json["sequence"] as! Int) + 1)
    resumed.close()
    await second.stop()
    await server.stop()
  }
}

/// A client of a port that answers nothing useful, for a test that only checks the connection ends.
private struct ConnectionProbe {
  let port: Int

  func get(_ path: String) async throws {
    let (_, _) = try await URLSession(configuration: .ephemeral).data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
  }
}
