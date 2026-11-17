import Foundation
import InsteonCore
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonService

/// A modem that answers Get IM Info, an empty ALL-Link database and direct commands, and
/// remembers the level each device was last sent.
actor RecordingModem: LinkingModem {
  private(set) var levels: [InsteonAddress: UInt8] = [:]
  let address = InsteonAddress(0x11, 0x22, 0x33)

  func send(_ command: SerialCommand) async throws {}

  func modemInfo() async throws -> ModemInfo {
    ModemInfo(address: address, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)
  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {
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
  func replies() async -> AsyncStream<ModemReply> { AsyncStream { _ in } }
}

/// A connection that stays up until a test drops it with an error.
final class HubLink: Sendable {
  let modem = RecordingModem()
  private let lifetime: AsyncThrowingStream<Void, any Error>
  private let continuation: AsyncThrowingStream<Void, any Error>.Continuation

  init() { (lifetime, continuation) = AsyncThrowingStream.makeStream() }

  func drop(with error: any Error) { continuation.finish(throwing: error) }

  fileprivate func waitUntilDropped() async throws { for try await _ in lifetime {} }
}

/// Opens the connections a test scripts, one per attempt.
actor ScriptedHubOpener: NetworkOpening {
  enum Attempt: Sendable {
    case fail(any Error)
    case connect(HubLink)
  }
  struct StillAway: Error {}

  private var script: [Attempt]

  init(_ script: [Attempt]) { self.script = script }

  func withNetwork(snapshot: NetworkSnapshot, _ body: @escaping @Sendable (DeviceNetwork) async throws -> Void) async throws {
    switch script.isEmpty ? Attempt.fail(StillAway()) : script.removeFirst() {
    case let .fail(error):
      throw error
    case let .connect(link):
      let network = DeviceNetwork(modem: link.modem, catalog: nil, snapshot: snapshot)
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
