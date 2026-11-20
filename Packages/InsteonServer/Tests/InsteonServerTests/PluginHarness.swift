import Foundation
import InsteonLoopbackTransport
import InsteonPluginKit
import Testing
@testable import InsteonServerSupport

extension RunningServer {
  /// The same server reached through another port, such as a transport's.
  func reached(through port: Int) -> RunningServer {
    RunningServer(task: task, port: port, capture: capture, retries: retries, reminders: reminders)
  }

  /// A client of the service with the scope, and its token.
  func token(named name: String, scope: String, password: String) async throws -> String {
    let created = try await request("/api/v1/clients", method: "POST", body: #"{"name":""# + name + #"","scope":""# + scope + #""}"#, password: password)
    return try #require((created.json["pairing"] as? [String: Any])?["credential"] as? String)
  }

  /// The service as a plugin reaches it.
  func plugin(token: String) -> ServiceClient {
    ServiceClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!, token: token)
  }
}

/// A reference transport running against a server, and what a test needs to stop it.
struct RunningTransport {
  let task: Task<Void, any Error>
  let port: Int

  /// Starts a transport and returns once it listens and has registered its route.
  static func start(for server: RunningServer, token: String, kind: String = LoopbackTransport.kind) async throws -> RunningTransport {
    let (ports, registered) = AsyncStream<Int>.makeStream()
    let transport = LoopbackTransport(service: server.plugin(token: token), upstreamPort: server.port, kind: kind)
    let task = Task { try await transport.run(onRegistered: { registered.yield($0) }) }
    let ended = Task { _ = await task.result; registered.finish() }
    var iterator = ports.makeAsyncIterator()
    let port = await iterator.next()
    ended.cancel()
    guard let port else {
      // The transport ended before it registered; its own error says why.
      try await task.value
      throw CancellationError()
    }
    return RunningTransport(task: task, port: port)
  }

  /// Stops the transport and returns once it has removed its route and closed its connections.
  func stop() async {
    task.cancel()
    _ = await task.result
  }
}
