import Foundation
import InsteonCore
import InsteonLinkingTestSupport
import InsteonService

/// A modem connection that stays up until a test drops it, as a Hub's polling stream does until
/// it fails.
final class ScriptedLink: Sendable {
  let modem: InMemoryModem
  private let lifetime: AsyncThrowingStream<Void, any Error>
  private let continuation: AsyncThrowingStream<Void, any Error>.Continuation

  init(modem: InMemoryModem = InMemoryModem()) {
    self.modem = modem
    (lifetime, continuation) = AsyncThrowingStream.makeStream()
  }

  /// Ends the connection with the error its reader failed with, or without one.
  func drop(with error: (any Error)? = nil) {
    continuation.finish(throwing: error)
  }

  fileprivate func waitUntilDropped() async throws {
    for try await _ in lifetime {}
  }
}

/// Opens the connections a test scripts, one per attempt, and says when each attempt starts.
actor ScriptedOpener: NetworkOpening {
  enum Attempt: Sendable {
    case fail(any Error)
    case connect(ScriptedLink)
  }

  struct StillAway: Error {}

  nonisolated let started: AsyncStream<Int>
  private let startedContinuation: AsyncStream<Int>.Continuation
  private var script: [Attempt]
  private let now: @Sendable () -> Date
  private(set) var snapshots: [NetworkSnapshot] = []
  private var report: (@Sendable () async -> Void)?

  init(_ script: [Attempt], now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }) {
    self.script = script
    self.now = now
    (started, startedContinuation) = AsyncStream.makeStream()
  }

  func append(_ attempt: Attempt) { script.append(attempt) }

  /// Reports one answered poll on the connection that is open, as a Hub's polling does.
  func poll() async { await report?() }

  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    try await withNetwork(snapshot: snapshot, onPollSucceeded: {}, body)
  }

  func withNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    report = onPollSucceeded
    snapshots.append(snapshot)
    let attempt = script.isEmpty ? Attempt.fail(StillAway()) : script.removeFirst()
    startedContinuation.yield(snapshots.count)
    switch attempt {
    case let .fail(error):
      throw error
    case let .connect(link):
      let network = DeviceNetwork(modem: link.modem, catalog: nil, snapshot: snapshot, now: now)
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await body(network) }
        group.addTask { try await link.waitUntilDropped() }
        defer { group.cancelAll() }
        _ = try await group.next()
      }
    }
  }
}
