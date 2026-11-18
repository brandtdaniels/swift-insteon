import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHTTP
import InsteonHubClient
import InsteonModem
import InsteonNetworking
import InsteonService
import Logging
import Testing
@testable import InsteonServerSupport

/// The real runner, router and service over a live listener, with a Hub or modem that is away,
/// comes back, and goes away again. Every wait is on a signal: the listener opening, a log record
/// or a retry delay the test releases.
@Suite(.timeLimit(.minutes(1)))
struct ServeTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  /// A running server and what a test needs to watch and stop it.
  private struct Server {
    let task: Task<Void, any Error>
    let port: Int
    let capture: ServerLogCapture
    let retries: ReleasableClock
    let reminders: ReleasableClock

    /// The first log record that satisfies `predicate`, waiting for one to arrive.
    func record(where predicate: @Sendable (ServerLogCapture.Record) -> Bool) async -> ServerLogCapture.Record? {
      if let found = capture.records.first(where: predicate) { return found }
      for await _ in capture.messages {
        if let found = capture.records.first(where: predicate) { return found }
      }
      return nil
    }

    func code(_ code: String) async -> ServerLogCapture.Record? {
      await record { $0.metadata["code"] == "\(code)" }
    }

    func stop() async { task.cancel(); _ = await task.result }

    func request(_ path: String, method: String = "GET", body: String? = nil, password: String) async throws -> (status: Int, json: [String: Any]) {
      var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
      request.httpMethod = method
      request.setValue("Basic " + Data(("insteon:" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
      if let body {
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Insteon-Request")
      }
      let (data, response) = try await URLSession.shared.data(for: request)
      return ((response as! HTTPURLResponse).statusCode, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }
  }

  private func scratch(savedDevice: Bool = true) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if savedDevice {
      let snapshot = NetworkSnapshot(
        registry: DeviceRegistrySnapshot(identities: [device: ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)]),
        devices: [device: NetworkDeviceState(level: 77, lastSeen: Date(timeIntervalSince1970: 1_800_000_000))]
      )
      try JSONFileDeviceRegistryStore(fileURL: directory.appendingPathComponent("state.json")).saveNetwork(snapshot)
    }
    return directory
  }

  /// Starts the server, waits until its listener is up, and returns it.
  private func start(_ directory: URL, extra: [String] = ["--hub", "192.168.1.20"], now: @escaping @Sendable () -> Date = { Date() }, openModem: @escaping ServerRunner.ModemOpener) async throws -> Server {
    let capture = ServerLogCapture()
    let port = try FreePort.unused()
    let retries = ReleasableClock()
    let reminders = ReleasableClock()
    let (listening, opened) = AsyncStream<Int>.makeStream()
    let timing = ServerRunner.Timing(clock: retries, jitter: { 0 }, reminderClock: reminders, now: now, onListening: { opened.yield($0) })
    let arguments = ["--state", directory.appendingPathComponent("state.json").path, "--port", String(port)] + extra
    let environment = ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"]
    let logger = capture.logger
    let task = Task { try await ServerRunner.run(arguments: arguments, environment: environment, logger: logger, openModem: openModem, timing: timing) }
    var ports = listening.makeAsyncIterator()
    guard let bound = await ports.next() else { throw CancellationError() }
    return Server(task: task, port: bound, capture: capture, retries: retries, reminders: reminders)
  }

  private func opener(_ scripted: ScriptedHubOpener) -> ServerRunner.ModemOpener {
    { _, _, snapshot, onPollSucceeded, body in try await scripted.withNetwork(snapshot: snapshot, onPollSucceeded: onPollSucceeded, body) }
  }

  // MARK: Hub away

  @Test func theHubBeingAwayAtStartKeepsTheServerUpServingTheSavedListAndLogsTheCause() async throws {
    let scripted = ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut)))])
    let server = try await start(try scratch(), openModem: opener(scripted))
    let record = try #require(await server.code("hub_unreachable"))
    #expect(record.level == .warning)
    #expect(record.message.contains("192.168.1.20:25105"))
    #expect(record.message.contains("retries"))
    #expect(!record.rendered.contains("hub-secret-pass"))

    let health = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect(health.json["status"] as? String == "starting")
    #expect((health.json["modem"] as? [String: Any])?["cause"] as? String == "hubUnreachable")
    #expect(health.json["snapshotAgeSeconds"] is Int)
    let list = try await server.request("/api/v1/devices", password: gatewayPassword)
    #expect(list.json["stale"] as? Bool == true)
    #expect((list.json["devices"] as? [[String: Any]])?.first?["value"] as? Int == 77)
    let refused = try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, password: gatewayPassword)
    #expect(refused.status == 503)
    #expect(refused.json["code"] as? String == "modemUnavailable")
    #expect(refused.json["sent"] as? Bool == false)
    await server.stop()
  }

  @Test func theServingLineFollowsTheStartingLineAndNeedsOnlyTheListener() async throws {
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut)))])))
    _ = await server.code("hub_unreachable")
    await server.stop()
    let messages = server.capture.records.map(\.message)
    let starting = try #require(messages.firstIndex { $0.hasPrefix("Starting") })
    let serving = try #require(messages.firstIndex { $0.hasPrefix("Serving") })
    #expect(starting < serving)
  }

  @Test(arguments: [401, 403]) func wrongHubCredentialsAtStartStayUpLogAnErrorAndRetrySlowly(_ status: Int) async throws {
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(HubError.unexpectedStatus(status))])))
    let record = try #require(await server.code("hub_credentials_rejected"))
    #expect(record.level == .error)
    #expect(record.message.contains("INSTEON_HUB_USERNAME"))
    #expect(record.message.contains("15 minutes"))
    #expect(!record.rendered.contains("hub-secret-pass"))
    let refused = try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, password: gatewayPassword)
    #expect(refused.json["cause"] as? String == "credentialsRejected")
    await server.stop()
  }

  @Test func aHubThatAnswersWithAServerErrorStaysUpAndSaysSo() async throws {
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(HubError.unexpectedStatus(503))])))
    let record = try #require(await server.code("hub_answered_with_error"))
    #expect(record.level == .warning)
    #expect(record.message.hasPrefix("The Hub answered with HTTP status 503."))
    await server.stop()
  }

  @Test func aModemThatIsNotAnsweringStaysUpAndSaysSo() async throws {
    let server = try await start(try scratch(), extra: ["--serial", "/dev/example-modem"], openModem: opener(ScriptedHubOpener([.fail(ModemError.timedOut(.getModemInfo))])))
    let record = try #require(await server.code("modem_unreachable"))
    #expect(record.message.hasPrefix("The modem isn't answering."))
    await server.stop()
  }

  @Test func aHubThatAnswersNothingToTheFirstModemRequestIsLoggedAsTheHubOnce() async throws {
    let link = HubLink()
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(ModemError.timedOut(.getModemInfo)), .connect(link)])))
    let record = try #require(await server.record { $0.level == .warning })
    #expect(record.metadata["code"] == "hub_unreachable")
    #expect(record.message.contains("192.168.1.20:25105"))
    server.retries.release()
    _ = await server.code("modem_connected")
    #expect(server.capture.records.filter { $0.level == .warning }.count == 1)
    await server.stop()
  }

  // MARK: Health liveness

  @Test func healthTellsAQuietLinkFromADeadOneWithoutAskingTheHub() async throws {
    let scripted = ScriptedHubOpener([.connect(HubLink())])
    let manual = ManualNow(Date(timeIntervalSince1970: 1_800_000_000))
    let server = try await start(try scratch(), now: { manual.now }, openModem: opener(scripted))
    _ = await server.code("modem_connected")
    let first = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect(first.json["lastPollAgeSeconds"] is NSNull)

    // A quiet house: the Hub answers polls and nothing else happens.
    manual.advance(by: 600)
    await scripted.poll()
    manual.advance(by: 4)
    let quiet = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect(quiet.json["status"] as? String == "ready")
    #expect(quiet.json["lastExchangeAgeSeconds"] as? Int == 604)
    #expect(quiet.json["lastPollAgeSeconds"] as? Int == 4)

    // The polls stop: the age keeps growing.
    manual.advance(by: 60)
    let silent = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect(silent.json["lastPollAgeSeconds"] as? Int == 64)
    await server.stop()
  }

  // MARK: Transitions, not retries

  @Test func eachChangeIsLoggedOnceAndRetriesOfTheSameCauseAreNot() async throws {
    let away = HubStoppedAnswering(underlyingError: URLError(.timedOut))
    let link = HubLink()
    let scripted = ScriptedHubOpener([.fail(away), .fail(away), .fail(away), .connect(link)])
    let server = try await start(try scratch(), openModem: opener(scripted))
    _ = await server.code("hub_unreachable")
    server.retries.release()
    server.retries.release()
    server.retries.release()
    let connected = try #require(await server.code("modem_connected"))
    #expect(connected.level == .info)
    #expect(server.capture.records.filter { $0.metadata["code"] == "hub_unreachable" }.count == 1)

    // The Hub goes away again: one more record, then the same cause repeating is silent.
    link.drop(with: away)
    _ = await server.record { $0.metadata["code"] == "hub_unreachable" && $0.metadata["reminder"] == "false" && server.capture.records.filter { $0.metadata["code"] == "hub_unreachable" }.count == 2 }
    #expect(server.capture.records.filter { $0.metadata["code"] == "hub_unreachable" }.count == 2)
    await server.stop()
  }

  @Test func oneOutageThatChangesBetweenUnreachableCausesIsLoggedOnceWithTheFirstCause() async throws {
    let link = HubLink()
    let scripted = ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut))), .fail(ModemError.timedOut(.getModemInfo)), .connect(link)])
    let server = try await start(try scratch(), openModem: opener(scripted))
    _ = await server.code("hub_unreachable")
    server.retries.release()
    server.retries.release()
    _ = await server.code("modem_connected")
    let warnings = server.capture.records.filter { $0.level == .warning }.compactMap { $0.metadata["code"] }
    #expect(warnings == ["hub_unreachable"])
    await server.stop()
  }

  @Test func aMaterialChangeOfCauseDuringAnOutageIsLoggedAgain() async throws {
    let link = HubLink()
    let scripted = ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut))), .fail(HubError.unexpectedStatus(401)), .connect(link)])
    let server = try await start(try scratch(), openModem: opener(scripted))
    _ = await server.code("hub_unreachable")
    server.retries.release()
    server.retries.release()
    _ = await server.code("modem_connected")
    let problems = server.capture.records.filter { $0.level != .info }.compactMap { $0.metadata["code"] }
    #expect(problems == ["hub_unreachable", "hub_credentials_rejected"])
    await server.stop()
  }

  @Test func anOutageThatLastsIsRepeatedAsAReminderNotAtEveryRetry() async throws {
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut)))])))
    _ = await server.code("hub_unreachable")
    server.reminders.release()
    let reminder = try #require(await server.record { $0.metadata["reminder"] == "true" })
    #expect(reminder.metadata["code"] == "hub_unreachable")
    await server.stop()
  }

  @Test func theHubReturningRestoresCommandsWithoutARestart() async throws {
    let first = HubLink()
    let second = HubLink()
    let away = HubStoppedAnswering(underlyingError: URLError(.timedOut))
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(away), .connect(first), .connect(second)])))
    _ = await server.code("hub_unreachable")
    server.retries.release()
    _ = await server.code("modem_connected")
    let ready = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect(ready.json["status"] as? String == "ready")
    let accepted = try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, password: gatewayPassword)
    #expect(accepted.status == 200)
    #expect(await first.modem.levels[device] == 0xFF)

    // Mid-run failure: HTTP stays up, the command is refused, and nothing is replayed.
    first.drop(with: away)
    _ = await server.record { $0.metadata["code"] == "hub_unreachable" }
    let degraded = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect(degraded.json["status"] as? String == "degraded")
    #expect((try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"off"}"#, password: gatewayPassword)).status == 503)
    server.retries.release()
    _ = await server.record { $0.metadata["code"] == "modem_connected" && server.capture.records.filter { $0.metadata["code"] == "modem_connected" }.count == 2 }
    #expect(await second.modem.levels.isEmpty)
    #expect((try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"off"}"#, password: gatewayPassword)).status == 200)
    #expect(await second.modem.levels[device] == 0)
    await server.stop()
  }

  // MARK: Still fatal

  @Test func aRefusedHubAddressStillEndsTheRunWithItsGuidedMessage() async throws {
    let directory = try scratch()
    let capture = ServerLogCapture()
    do {
      try await ServerRunner.run(
        arguments: ["--hub", "203.0.113.5", "--port", String(try FreePort.unused()), "--state", directory.appendingPathComponent("state.json").path],
        environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "u", "INSTEON_HUB_PASSWORD": "p"],
        logger: capture.logger,
        openModem: { _, _, _, _, _ in Issue.record("no connection should open") }
      )
      Issue.record("the run should end")
    } catch {
      #expect(ServerFailure(error).code == .hubAddressRefused)
      #expect(ServerFailure(error).exitStatus == ServerFailure.configurationStatus)
    }
  }

  @Test func aHubAddressTheOpenerRefusesEndsTheRunInsteadOfRetrying() async throws {
    let directory = try scratch()
    do {
      try await ServerRunner.run(
        arguments: ["--hub", "192.168.1.20", "--port", String(try FreePort.unused()), "--state", directory.appendingPathComponent("state.json").path],
        environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "u", "INSTEON_HUB_PASSWORD": "p"],
        logger: ServerLogCapture().logger,
        openModem: { _, _, _, _, _ in throw HubAddressRefused(host: "example.com") }
      )
      Issue.record("the run should end")
    } catch {
      #expect(ServerFailure(error).code == .hubAddressRefused)
    }
  }

  @Test func aSerialPathThatDoesNotExistAtStartEndsTheRunButAnUnpluggedModemLaterDoesNot() async throws {
    let missing = SerialPortError.cannotOpen(path: "/dev/example-modem", code: ENOENT)
    let directory = try scratch()
    do {
      try await ServerRunner.run(
        arguments: ["--serial", "/dev/example-modem", "--port", String(try FreePort.unused()), "--state", directory.appendingPathComponent("state.json").path],
        environment: ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword],
        logger: ServerLogCapture().logger,
        openModem: { _, _, _, _, _ in throw missing }
      )
      Issue.record("the run should end")
    } catch {
      #expect(ServerFailure(error).code == .serialPathMissing)
    }

    // The same error once the modem has worked is the modem being unplugged: stay up.
    let link = HubLink()
    let server = try await start(try scratch(), extra: ["--serial", "/dev/example-modem"], openModem: opener(ScriptedHubOpener([.connect(link), .fail(missing)])))
    _ = await server.code("modem_connected")
    link.drop(with: missing)
    #expect(await server.code("modem_unreachable") != nil)
    await server.stop()
  }
}
