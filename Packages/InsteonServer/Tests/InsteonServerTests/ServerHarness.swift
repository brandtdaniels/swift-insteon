import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonCore
import InsteonHubClient
import InsteonService
import Logging
import Testing
@testable import InsteonServerSupport

/// A running server and what a test needs to watch and stop it.
struct RunningServer {
  let task: Task<Void, any Error>
  let port: Int
  let capture: ServerLogCapture
  let retries: ReleasableClock
  let reminders: ReleasableClock
  /// Prints what the server logged if the test is still running after 90 seconds, so a hang that
  /// can't be reproduced shows where the run stopped. Stopping the server cancels it.
  var watchdog: Task<Void, Never>? = nil

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

  func stop() async { watchdog?.cancel(); task.cancel(); _ = await task.result }

  func request(_ path: String, method: String = "GET", body: String? = nil, password: String, bearer: String? = nil) async throws -> (status: Int, json: [String: Any]) {
    let result = try await exchange(path, method: method, body: body, headers: [:], password: password, bearer: bearer)
    return (result.status, result.json)
  }

  /// A request with extra headers, answering the response headers as well.
  func exchange(_ path: String, method: String = "GET", body: String? = nil, headers: [String: String], password: String, bearer: String? = nil) async throws -> (status: Int, json: [String: Any], headers: [String: String]) {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.timeoutInterval = 20
    request.httpMethod = method
    request.setValue(bearer.map { "Bearer " + $0 } ?? "Basic " + Data(("insteon:" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = Data(body.utf8)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if body != nil || method == "DELETE" || method == "POST" { request.setValue("1", forHTTPHeaderField: "X-Insteon-Request") }
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    // A session of its own for each request, so no pooled connection to a port that has closed
    // is reused, and a request that stalls fails and names what it was waiting for.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.httpMaximumConnectionsPerHost = 1
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw error
    } catch {
      throw HarnessRequestError(description: "\(method) \(path) on port \(port) failed: \(error)")
    }
    let http = response as! HTTPURLResponse
    var received: [String: String] = [:]
    for (name, value) in http.allHeaderFields { received[String(describing: name).lowercased()] = String(describing: value) }
    return (http.statusCode, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:], received)
  }
}

/// What a suite needs to run the real server over a scripted modem connection.
protocol ServingTests {
  var gatewayPassword: String { get }
  var device: InsteonAddress { get }
}

extension ServingTests {
  func scratch(savedDevice: Bool = true, identified: Bool = true) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-server-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if savedDevice {
      let snapshot = NetworkSnapshot(
        registry: DeviceRegistrySnapshot(identities: identified ? [device: ReportedIdentity(category: 1, subcategory: 125, firmwareVersion: 69)] : [:]),
        devices: [device: NetworkDeviceState(level: 77, lastSeen: Date(timeIntervalSince1970: 1_800_000_000))]
      )
      try JSONFileDeviceRegistryStore(fileURL: directory.appendingPathComponent("state.json")).saveNetwork(snapshot)
    }
    return directory
  }

  /// Starts the server, waits until its listener is up, and returns it.
  func start(_ directory: URL, extra: [String] = ["--hub", "192.168.1.20"], environment extraEnvironment: [String: String]? = nil, hubPro: ServerRunner.HubProAccess = .live, now: @escaping @Sendable () -> Date = { Date() }, openModem: @escaping ServerRunner.ModemOpener) async throws -> RunningServer {
    // Another suite can take the port between choosing it and binding it: the run ends before it
    // listens, and a different port is chosen.
    for _ in 0..<5 {
      let capture = ServerLogCapture()
      let port = try FreePort.unused()
      let retries = ReleasableClock()
      let reminders = ReleasableClock()
      let (listening, opened) = AsyncStream<Int>.makeStream()
      let timing = ServerRunner.Timing(clock: retries, jitter: { 0 }, reminderClock: reminders, now: now, onListening: { opened.yield($0) })
      let arguments = ["--state", directory.appendingPathComponent("state.json").path, "--port", String(port)] + extra
      let environment = extraEnvironment ?? ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"]
      let logger = capture.logger
      let task = Task { try await ServerRunner.run(arguments: arguments, environment: environment, logger: logger, openModem: openModem, timing: timing, hubPro: hubPro) }
      let ended = Task { _ = await task.result; opened.finish() }
      var ports = listening.makeAsyncIterator()
      let bound = await ports.next()
      ended.cancel()
      if let bound {
        let watchdog = Task {
          do { try await Task.sleep(for: .seconds(90)) } catch { return }
          print("WATCHDOG: a test has run for 90 seconds with its server up on port \(bound). The server logged:\n" + capture.records.map(\.rendered).joined(separator: "\n"))
        }
        return RunningServer(task: task, port: bound, capture: capture, retries: retries, reminders: reminders, watchdog: watchdog)
      }
    }
    throw CancellationError()
  }

  func opener(_ scripted: ScriptedHubOpener) -> ServerRunner.ModemOpener {
    { _, _, snapshot, onPollSucceeded, body in try await scripted.withNetwork(snapshot: snapshot, onPollSucceeded: onPollSucceeded, body) }
  }
}

/// A request a test sent that did not complete, with what it was.
struct HarnessRequestError: Error, CustomStringConvertible {
  let description: String
}
