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
actor ScriptedCalls: HomeCalls {
  let label: String
  private var script: [Script]
  private(set) var asked: [String] = []

  init(label: String, script: [Script] = []) {
    self.label = label
    self.script = script
  }

  private func next() -> Script { script.isEmpty ? .answer : script.removeFirst() }

  func devices() async throws -> [ServiceDevice] {
    asked.append("devices")
    switch next() {
    case .answer: return [device(value: label == "local" ? 1 : 2)]
    case .notReached: throw HomePathError.notReached("scripted")
    case .interrupted: throw HomePathError.interrupted
    case .unauthorized: throw HomePathError.unauthorized
    case .badResponse: throw HomePathError.badResponse
    case .forbidden: throw HomePathError.forbidden
    }
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    asked.append("execute")
    switch next() {
    case .answer: return CommandReceipt(address: command.address, outcome: .acknowledged, status: nil)
    case .notReached: throw HomePathError.notReached("scripted")
    case .interrupted: throw HomePathError.interrupted
    case .unauthorized: throw HomePathError.unauthorized
    case .badResponse: throw HomePathError.badResponse
    case .forbidden: throw HomePathError.forbidden
    }
  }
}

/// A path whose openings succeed or fail from a script, and that counts them.
actor ScriptedPath: HomePath {
  nonisolated let name: String
  let calls: ScriptedCalls
  private let served: any HomeCalls
  private var openings: [HomePathError?]
  private(set) var openCount = 0

  init(_ name: String, openings: [HomePathError?] = [], calls: ScriptedCalls? = nil, gated: GatedCalls? = nil) {
    self.name = name
    self.openings = openings
    let scripted = calls ?? ScriptedCalls(label: name)
    self.calls = scripted
    self.served = gated ?? scripted
  }

  func open() async throws -> any HomeCalls {
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
actor GatedCalls: HomeCalls {
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
    throw HomePathError.interrupted
  }

  func execute(_ command: ServiceCommand) async throws -> CommandReceipt { throw HomePathError.interrupted }

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
