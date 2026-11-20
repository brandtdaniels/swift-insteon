import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a notifier reads the service's events.
public protocol NotificationStreaming: Sendable {
  /// The sequence of events one connection reads.
  associatedtype Events: AsyncSequence where Events.Element == StreamItem

  /// The events after `lastEventID`, or the live stream when it is `nil`.
  ///
  /// The sequence ends when the stream ends, and throws when the connection fails or the service
  /// refuses the credential (``PluginError/unauthorized(status:code:)``).
  func events(after lastEventID: String?) -> Events

  /// How many notification rules the service holds.
  func ruleCount() async throws -> Int
}

/// Reads `GET /api/v1/events` and `GET /api/v1/notification-rules` from the service with a `read` token.
public struct ServiceEventSource: NotificationStreaming {
  private let service: ServiceClient

  /// Creates a source.
  /// - Parameter service: The service, with a `read` token.
  public init(service: ServiceClient) {
    self.service = service
  }

  public func events(after lastEventID: String?) -> Items {
    var request = service.authorizedRequest("GET", "/api/v1/events")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    if let lastEventID { request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID") }
    request.timeoutInterval = 120
    return Items(chunks: Self.chunks(of: request))
  }

  public func ruleCount() async throws -> Int {
    let response = try await service.send("GET", "/api/v1/notification-rules")
    if let failure = response.failure { throw failure }
    guard let rules = ((try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any])?["rules"] as? [Any] else { throw PluginError.malformedResponse }
    return rules.count
  }

  fileprivate enum Chunk: Sendable {
    case refused(status: Int)
    case data(Data)
  }

  private static func chunks(of request: URLRequest) -> AsyncThrowingStream<Chunk, any Error> {
    AsyncThrowingStream { continuation in
      let session = URLSession(configuration: .ephemeral, delegate: StreamDelegate(continuation: continuation), delegateQueue: nil)
      let task = session.dataTask(with: request)
      continuation.onTermination = { _ in
        task.cancel()
        session.invalidateAndCancel()
      }
      task.resume()
    }
  }

  /// Passes a response's status and bytes on. It holds no state of its own.
  private final class StreamDelegate: NSObject, URLSessionDataDelegate, Sendable {
    let continuation: AsyncThrowingStream<Chunk, any Error>.Continuation

    init(continuation: AsyncThrowingStream<Chunk, any Error>.Continuation) {
      self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
      if !reportRefusal(of: dataTask) { continuation.yield(.data(data)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
      if reportRefusal(of: task) { return }
      if error == nil { continuation.finish() } else { continuation.finish(throwing: PluginError.unreachable) }
    }

    /// Tells the reader when the service answered with anything but a stream, and returns whether it did.
    private func reportRefusal(of task: URLSessionTask) -> Bool {
      guard let http = task.response as? HTTPURLResponse, http.statusCode != 200 else { return false }
      continuation.yield(.refused(status: http.statusCode))
      return true
    }
  }

  /// The events one connection reads, as they arrive.
  public struct Items: AsyncSequence {
    public typealias Element = StreamItem
    fileprivate let chunks: AsyncThrowingStream<Chunk, any Error>

    public func makeAsyncIterator() -> Iterator { Iterator(chunks: chunks.makeAsyncIterator()) }

    /// Reads events from the connection's chunks.
    public struct Iterator: AsyncIteratorProtocol {
      fileprivate var chunks: AsyncThrowingStream<Chunk, any Error>.AsyncIterator
      private var parser = ServerSentEventParser()
      private var ready: [StreamItem] = []

      fileprivate init(chunks: AsyncThrowingStream<Chunk, any Error>.AsyncIterator) {
        self.chunks = chunks
      }

      public mutating func next() async throws -> StreamItem? {
        while true {
          if !ready.isEmpty { return ready.removeFirst() }
          guard let chunk = try await chunks.next() else { return nil }
          switch chunk {
          case let .refused(status):
            throw (status == 401 || status == 403) ? PluginError.unauthorized(status: status, code: nil) : PluginError.rejected(status: status, code: nil)
          case let .data(data):
            ready = parser.feed(data).compactMap(StreamItem.init)
          }
        }
      }
    }
  }
}
