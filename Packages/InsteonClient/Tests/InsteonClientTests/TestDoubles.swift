import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonClient
import InsteonNetworking
import InsteonProtocol
import InsteonService

let lampAddress = InsteonAddress(0x1A, 0x2B, 0x3C)

func device(_ address: InsteonAddress = lampAddress, value: UInt8? = 0x80) -> ServiceDevice {
  ServiceDevice(address: address, productName: "Example Dimmer", canTurnOnAndOff: true, canDim: true, value: value, lastAnsweredAt: nil)
}

/// What a scripted path's calls do next.
enum Script: Sendable {
  case answer
  case notReached
  case interrupted
  case unauthorized
  case badResponse
  case forbidden
}

/// Calls that answer from a script and record what they were asked.
actor ScriptedCalls: ConnectionCalls {
  let label: String
  private var script: [Script]
  private(set) var asked: [String] = []
  private(set) var isClosed = false

  func close() async { isClosed = true }

  init(label: String, script: [Script] = []) {
    self.label = label
    self.script = script
  }

  private func next() -> Script { script.isEmpty ? .answer : script.removeFirst() }

  func devices() async throws -> [ServiceDevice] {
    asked.append("devices")
    switch next() {
    case .answer: return [device(value: label == "local" ? 1 : 2)]
    case .notReached: throw ConnectionPathError.notReached("scripted")
    case .interrupted: throw ConnectionPathError.interrupted
    case .unauthorized: throw ConnectionPathError.unauthorized
    case .badResponse: throw ConnectionPathError.badResponse
    case .forbidden: throw ConnectionPathError.forbidden
    }
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    asked.append("execute")
    switch next() {
    case .answer: return CommandReceipt(address: command.address, outcome: .acknowledged, status: nil)
    case .notReached: throw ConnectionPathError.notReached("scripted")
    case .interrupted: throw ConnectionPathError.interrupted
    case .unauthorized: throw ConnectionPathError.unauthorized
    case .badResponse: throw ConnectionPathError.badResponse
    case .forbidden: throw ConnectionPathError.forbidden
    }
  }
}

/// A path whose openings succeed or fail from a script, and that counts them.
actor ScriptedPath: ConnectionPath {
  nonisolated let name: String
  let calls: ScriptedCalls
  private let served: any ConnectionCalls
  private var openings: [ConnectionPathError?]
  private(set) var openCount = 0

  init(_ name: String, openings: [ConnectionPathError?] = [], calls: ScriptedCalls? = nil, gated: GatedCalls? = nil) {
    self.name = name
    self.openings = openings
    let scripted = calls ?? ScriptedCalls(label: name)
    self.calls = scripted
    self.served = gated ?? scripted
  }

  func open() async throws -> any ConnectionCalls {
    openCount += 1
    if !openings.isEmpty, let failure = openings.removeFirst() { throw failure }
    return served
  }
}

/// An HTTP client that answers from a closure and records each request.
actor FakeHTTPClient: HTTPClient {
  private(set) var requests: [URLRequest] = []
  private let respond: @Sendable (URLRequest) throws -> HTTPResponse

  init(_ respond: @escaping @Sendable (URLRequest) throws -> HTTPResponse) { self.respond = respond }

  func send(_ request: URLRequest) async throws -> HTTPResponse {
    requests.append(request)
    return try respond(request)
  }

  var lines: [String] { requests.map { "\($0.httpMethod ?? "GET") \($0.url?.absoluteString ?? "")" } }
}

func json(_ text: String, status: Int = 200) -> HTTPResponse { HTTPResponse(statusCode: status, body: Data(text.utf8)) }

struct Unplugged: Error {}

/// Calls whose first read waits until the test lets it go, then fails; every later read fails at once.
actor GatedCalls: ConnectionCalls {
  private var reads = 0
  private var release: CheckedContinuation<Void, Never>?
  private var heldSignal: CheckedContinuation<Void, Never>?
  private var isHeld = false

  func devices() async throws -> [ServiceDevice] {
    reads += 1
    if reads == 1 {
      isHeld = true
      heldSignal?.resume()
      heldSignal = nil
      await withCheckedContinuation { release = $0 }
    }
    throw ConnectionPathError.interrupted
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt { throw ConnectionPathError.interrupted }

  /// Returns once the first read is waiting.
  func waitUntilHeld() async {
    if isHeld { return }
    await withCheckedContinuation { heldSignal = $0 }
  }

  func letGo() {
    release?.resume()
    release = nil
  }
}

/// A path whose first opening waits until the test lets it go; later openings return at once.
/// Each opening makes calls of its own.
actor GatedOpenPath: ConnectionPath {
  nonisolated let name = "gated"
  private(set) var opened: [ScriptedCalls] = []
  private var release: CheckedContinuation<Void, Never>?
  private var signal: CheckedContinuation<Void, Never>?
  private var isWaiting = false

  func open() async throws -> any ConnectionCalls {
    let calls = ScriptedCalls(label: "opening-\(opened.count + 1)")
    opened.append(calls)
    if opened.count == 1 {
      isWaiting = true
      signal?.resume()
      signal = nil
      await withCheckedContinuation { release = $0 }
    }
    return calls
  }

  func waitUntilFirstOpeningIsWaiting() async {
    if isWaiting { return }
    await withCheckedContinuation { signal = $0 }
  }

  func letFirstOpeningGo() {
    release?.resume()
    release = nil
  }
}

/// What one subscription of a scripted path's calls does.
enum EventSubscription: Sendable {
  /// Delivers the items, then ends as told.
  case items([SequencedItem], ending: Ending)
  /// Refuses the subscription.
  case refuse(ConnectionPathError)

  enum Ending: Sendable {
    case lost(ConnectionPathError)
    case slowConsumer
    case held
  }
}

/// Calls that serve numbered events from a script and record the cursor each subscription asked for.
actor EventCalls: ConnectionCalls {
  private var script: [EventSubscription]
  private(set) var requested: [EventCursor?] = []

  init(script: [EventSubscription]) { self.script = script }

  func devices() async throws -> [ServiceDevice] { [device()] }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    CommandReceipt(address: command.address, outcome: .acknowledged, status: nil)
  }

  func sequencedEvents(after cursor: EventCursor?) async throws -> SequencedEvents {
    requested.append(cursor)
    let next = script.isEmpty ? EventSubscription.items([], ending: .held) : script.removeFirst()
    switch next {
    case let .refuse(error): throw error
    case let .items(items, ending):
      return SequencedEvents(AsyncThrowingStream { continuation in
        for item in items { continuation.yield(item) }
        switch ending {
        case let .lost(error): continuation.finish(throwing: error)
        case .slowConsumer: continuation.finish(throwing: ServiceEventError.slowConsumer)
        case .held: break
        }
      })
    }
  }
}

/// A path whose openings succeed or fail from a script and whose calls serve scripted events.
actor EventPath: ConnectionPath {
  nonisolated let name: String
  let calls: EventCalls
  private var openings: [ConnectionPathError?]
  private(set) var openCount = 0

  init(_ name: String, openings: [ConnectionPathError?] = [], subscriptions: [EventSubscription]) {
    self.name = name
    self.openings = openings
    calls = EventCalls(script: subscriptions)
  }

  func open() async throws -> any ConnectionCalls {
    openCount += 1
    if !openings.isEmpty, let failure = openings.removeFirst() { throw failure }
    return calls
  }
}

func cursor(_ sequence: UInt64, run: String = "run1") -> EventCursor { EventCursor(runID: run, sequence: sequence) }

func heard(_ sequence: UInt64, run: String = "run1") -> SequencedItem {
  .event(.statusChanged(lampAddress), cursor(sequence, run: run))
}

/// An HTTP client that answers requests from a closure and opens event streams from a script.
actor StreamingHTTPClient: HTTPClient {
  /// What the next stream request gets.
  enum Opening: Sendable {
    case stream(status: Int, AsyncThrowingStream<Data, any Error>)
    case failure
  }

  private(set) var requests: [URLRequest] = []
  private var openings: [Opening]
  private let respond: @Sendable (URLRequest) throws -> HTTPResponse

  init(openings: [Opening], respond: @escaping @Sendable (URLRequest) throws -> HTTPResponse = { _ in
    json(#"{"version":1,"status":"ready","modem":{"connected":true,"cause":null}}"#)
  }) {
    self.openings = openings
    self.respond = respond
  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {
    requests.append(request)
    return try respond(request)
  }

  func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
    requests.append(request)
    guard !openings.isEmpty else { throw Unplugged() }
    switch openings.removeFirst() {
    case let .stream(status, body): return HTTPStreamResponse(statusCode: status, headers: ["Content-Type": "text/event-stream"], body: body)
    case .failure: throw Unplugged()
    }
  }

  var streamRequests: [URLRequest] { requests.filter { $0.url?.path == "/api/v1/events" } }
}

/// A body a test feeds bytes to.
struct Feed {
  let body: AsyncThrowingStream<Data, any Error>
  private let continuation: AsyncThrowingStream<Data, any Error>.Continuation

  init() { (body, continuation) = AsyncThrowingStream<Data, any Error>.makeStream() }

  func send(_ text: String) { continuation.yield(Data(text.utf8)) }
  func send(bytes: [UInt8]) { continuation.yield(Data(bytes)) }
  func end() { continuation.finish() }
  func fail() { continuation.finish(throwing: Unplugged()) }
}
