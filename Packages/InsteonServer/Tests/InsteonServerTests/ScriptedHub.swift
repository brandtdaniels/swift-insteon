import Foundation
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonService

/// A modem that answers Get IM Info, an empty ALL-Link database and direct commands, and
/// remembers the level each device was last sent.
actor RecordingModem: LinkingModem {
  private(set) var levels: [InsteonAddress: UInt8] = [:]
  let address = InsteonAddress(0x11, 0x22, 0x33)
  /// How many requests each device was sent, counting those it then failed.
  private(set) var requestCounts: [InsteonAddress: Int] = [:]
  private var failures: [InsteonAddress: any Error] = [:]
  private var held: (stream: AsyncStream<Void>, release: AsyncStream<Void>.Continuation)?
  private var entered: AsyncStream<Void>.Continuation?

  /// Makes every request to a device throw `error`, as a device that never answers does.
  func fail(_ device: InsteonAddress, with error: any Error) { failures[device] = error }

  /// Holds each request until ``release()``, and returns a stream that yields when one arrives.
  func hold() -> AsyncStream<Void> {
    let (stream, release) = AsyncStream<Void>.makeStream()
    held = (stream, release)
    let (arrivals, arrived) = AsyncStream<Void>.makeStream()
    entered = arrived
    return arrivals
  }

  func release() { held?.release.finish(); held = nil }

  func send(_ command: SerialCommand) async throws {}

  func modemInfo() async throws -> ModemInfo {
    ModemInfo(address: address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)
  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {
    if let held {
      entered?.yield()
      for await _ in held.stream {}
    }
    requestCounts[message.destination, default: 0] += 1
    if let error = failures[message.destination] { throw error }
    let command = message.command
    if [0x11, 0x13].contains(command.command1) {
      levels[message.destination] = command.command1 == 0x11 ? command.command2 : 0x00
    }
    return ReceivedMessage(sender: message.destination, destination: address, flags: MessageFlags(messageType: .directAcknowledgment), command: command)
  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage { throw ModemError.connectionClosed }
  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] { [] }
  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse { throw ModemError.connectionClosed }
  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] { [] }
  func allLinkRecords() async throws -> [AllLinkRecord] { [] }
  private var listeners: [AsyncStream<ModemReply>.Continuation] = []
  /// Broadcasts made before anyone listened, handed to the first listener. A real modem's
  /// messages wait in the connection until they are read, so a test that fires as soon as the
  /// server is up never loses one to a service that hasn't started listening yet.
  private var heldBeforeAnyoneListened: [ModemReply] = []

  func sendAllLinkCommand(group: AllLinkGroupNumber, command: Command, timeout: Duration) async throws -> AllLinkCleanupReport {

    throw ModemError.rejected(.sendAllLinkCommand)

  }

  func replies() async -> AsyncStream<ModemReply> {
    let (stream, continuation) = AsyncStream<ModemReply>.makeStream()
    for reply in heldBeforeAnyoneListened { continuation.yield(reply) }
    heldBeforeAnyoneListened = []
    listeners.append(continuation)
    return stream
  }

  /// A device broadcasts a command to one of its ALL-Link groups, as a sensor does when it reports.
  func broadcastGroupCommand(from device: InsteonAddress, group: UInt8, command1: UInt8) {
    let message = ReceivedMessage(sender: device, destination: InsteonAddress(0x00, 0x00, group), flags: MessageFlags(messageType: .allLinkBroadcast), command: Command(command1: command1, command2: 0x00))
    if listeners.isEmpty {
      heldBeforeAnyoneListened.append(.messageReceived(message))
      return
    }
    for listener in listeners { listener.yield(.messageReceived(message)) }
  }

}

/// A connection that stays up until a test drops it with an error.
///
/// Any number of attempts can wait on it, one after another or together, and one that leaves, as
/// a run does that lost its port to another suite, doesn't end the wait of the others.
final class HubLink: @unchecked Sendable {
  let modem = RecordingModem()
  private let lock = NSLock()
  private var dropped: (any Error)?
  private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

  func drop(with error: any Error) {
    let ending: [CheckedContinuation<Void, any Error>] = lock.withLock {
      guard dropped == nil else { return [] }
      dropped = error
      defer { waiters = [:] }
      return Array(waiters.values)
    }
    for waiter in ending { waiter.resume(throwing: error) }
  }

  /// How many attempts are waiting on the connection.
  var waiterCount: Int { lock.withLock { waiters.count } }

  func waitUntilDropped() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
        let error: (any Error)? = lock.withLock {
          if let dropped { return dropped }
          // Canceled before it waited: the cancellation handler found no waiter to end.
          if Task.isCancelled { return CancellationError() }
          waiters[id] = waiter
          return nil
        }
        if let error { waiter.resume(throwing: error) }
      }
    } onCancel: {
      let waiter = lock.withLock { waiters.removeValue(forKey: id) }
      waiter?.resume(throwing: CancellationError())
    }
  }
}

/// Opens the connections a test scripts, one per attempt.
actor ScriptedHubOpener: NetworkOpening {
  enum Attempt: Sendable {
    case fail(any Error)
    case connect(HubLink)
  }
  struct StillAway: Error {}

  private let catalog: DeviceCatalog?
  private let deviceClock: any Clock<Duration>
  private var script: [Attempt]
  private var report: (@Sendable () async -> Void)?

  init(_ script: [Attempt], catalog: DeviceCatalog? = nil, clock: any Clock<Duration> = ContinuousClock()) {
    self.script = script
    self.catalog = catalog
    deviceClock = clock
  }

  /// Reports one answered poll on the connection that is open, as a Hub's polling does.
  func poll() async { await report?() }

  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    try await withNetwork(snapshot: snapshot, onPollSucceeded: {}, body)
  }

  func withNetwork(snapshot: NetworkSnapshot, onPollSucceeded: @escaping @Sendable () async -> Void, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    report = onPollSucceeded
    switch script.isEmpty ? Attempt.fail(StillAway()) : script.removeFirst() {
    case let .fail(error):
      throw error
    case let .connect(link):
      let network = DeviceNetwork(modem: link.modem, catalog: catalog, snapshot: snapshot, clock: deviceClock)
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await body(network) }
        group.addTask { try await link.waitUntilDropped() }
        defer { group.cancelAll() }
        _ = try await group.next()
      }
    }
  }
}

/// A clock whose sleeps end when a test releases them, one release per sleep.
final class ReleasableClock: Clock, Sendable {
  typealias Instant = ContinuousClock.Instant
  private let releases: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() { (releases, continuation) = AsyncStream.makeStream() }

  var now: Instant { .now }
  var minimumResolution: Duration { .zero }

  func release() { continuation.yield() }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    for await _ in releases { return }
    throw CancellationError()
  }
}

/// Saves nothing, as a read-only state directory would not.
struct NoSnapshots: SnapshotPersisting {
  func save(_ snapshot: NetworkSnapshot) async -> PersistenceOutcome { .saved }
}

/// A date a test moves by hand.
final class ManualNow: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) { self.date = date }

  var now: Date { lock.withLock { date } }

  func advance(by seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

/// A clock that reads 30 seconds later each time it is read, so two reports of the same press are never
/// taken for one. Nothing sleeps on it.
final class SteppingClock: Clock, @unchecked Sendable {
  typealias Instant = ContinuousClock.Instant
  private let lock = NSLock()
  private let base = ContinuousClock.now
  private var reads: Int64 = 0

  var now: Instant { lock.withLock { reads += 1; return base.advanced(by: .seconds(30 * reads)) } }
  var minimumResolution: Duration { .zero }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws { throw CancellationError() }
}
