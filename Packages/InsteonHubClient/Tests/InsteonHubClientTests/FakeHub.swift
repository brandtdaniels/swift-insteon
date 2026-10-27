import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking

/// An `HTTPClient` that behaves like a Hub: it keeps a 100-byte reply buffer, starts it over
/// for each command, and answers each command with bytes chosen by a script.
actor FakeHub: HTTPClient {

  private(set) var buffer = [UInt8](repeating: 0, count: 100)

  private(set) var endIndex = 0

  private(set) var requests: [String] = []

  /// Every command written, in order, for tests that need to wait for a write.
  nonisolated let writes: AsyncStream<[UInt8]>

  private let writesContinuation: AsyncStream<[UInt8]>.Continuation

  private let respond: @Sendable ([UInt8]) -> [UInt8]

  private let status: Int

  /// - Parameters:
  ///   - status: The HTTP status for every request.
  ///   - respond: Given each command written, returns what the modem puts in the buffer.
  init(status: Int = 200, respond: @escaping @Sendable ([UInt8]) -> [UInt8] = { $0 + [0x06] }) {

    (writes, writesContinuation) = AsyncStream.makeStream()
    self.status = status
    self.respond = respond

  }

  /// Puts bytes in the buffer as if the modem had received them, such as a device's message.
  func deliver(_ bytes: [UInt8]) {

    for byte in bytes {

      buffer[endIndex] = byte
      endIndex = (endIndex + 1) % buffer.count

    }

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    let path = request.url?.path ?? ""
    let query = request.url?.query ?? ""
    requests.append("\(request.httpMethod ?? "") \(path)")

    guard status == 200 else {

      return HTTPResponse(statusCode: status)

    }

    switch path {
    case "/3":
      let command = Self.bytes(fromHex: String(query.prefix { $0 != "=" }))
      clear()
      deliver(respond(command))
      writesContinuation.yield(command)
    case "/1":
      clear()
    case "/buffstatus.xml":
      let digits = buffer.map(Self.hex).joined() + Self.hex(UInt8(endIndex * 2))
      return HTTPResponse(statusCode: 200, body: Data("<response><BS>\(digits)</BS></response>".utf8))
    default:
      return HTTPResponse(statusCode: 404)
    }

    return HTTPResponse(statusCode: 200)

  }

  private func clear() {

    buffer = [UInt8](repeating: 0, count: buffer.count)
    endIndex = 0

  }

  private static func hex(_ byte: UInt8) -> String {

    byte < 0x10 ? "0" + String(byte, radix: 16, uppercase: true) : String(byte, radix: 16, uppercase: true)

  }

  private static func bytes(fromHex text: String) -> [UInt8] {

    let digits = Array(text)

    return stride(from: 0, to: digits.count - 1, by: 2).compactMap { UInt8(String(digits[$0...$0 + 1]), radix: 16) }

  }

}
