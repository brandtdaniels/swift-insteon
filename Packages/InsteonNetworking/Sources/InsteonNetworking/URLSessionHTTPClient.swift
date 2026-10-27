import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Adapts `URLSession` to ``HTTPClient``.
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {

  // `URLSession` is thread-safe; it isn't marked `Sendable` on every platform.
  private let session: URLSession

  /// Creates a client that sends requests with a session.
  ///
  /// - Parameter session: The session to send requests with. Defaults to the shared session.
  public init(session: URLSession = .shared) {

    self.session = session

  }

  /// Sends a request with the session.
  ///
  /// - Parameter request: The request to send.
  /// - Returns: The response's status, headers and body.
  /// - Throws: The session's error if the request failed, or
  ///   ``HTTPClientError/nonHTTPResponse`` if the response wasn't HTTP.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    let (data, response) = try await data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {

      throw HTTPClientError.nonHTTPResponse

    }

    var headers: [String: String] = [:]

    for case let (name as String, value as String) in httpResponse.allHeaderFields {

      headers[name] = value

    }

    return HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)

  }

  private func data(for request: URLRequest) async throws -> (Data, URLResponse) {

    #if canImport(FoundationNetworking)
    // swift-corelibs-foundation lacks an async API, so bridge the completion handler, and cancel
    // the data task when the calling task is canceled, as the async API on Apple platforms does.
    let cancellation = DataTaskCancellation()

    return try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { continuation in

        let task = session.dataTask(with: request) { data, response, error in

          if let error {

            continuation.resume(throwing: error)

          } else if let response {

            continuation.resume(returning: (data ?? Data(), response))

          } else {

            continuation.resume(throwing: URLError(.badServerResponse))

          }

        }

        cancellation.start(task)

      }

    } onCancel: {

      cancellation.cancel()

    }
    #else
    return try await session.data(for: request)
    #endif

  }

}

#if canImport(FoundationNetworking)
/// Starts a data task and cancels it if cancellation was requested before or after it started.
private final class DataTaskCancellation: @unchecked Sendable {

  // `lock` guards `task` and `isCanceled`.
  private let lock = NSLock()

  private var task: URLSessionDataTask?

  private var isCanceled = false

  func start(_ task: URLSessionDataTask) {

    let isCanceled = lock.withLock {

      self.task = task

      return self.isCanceled

    }

    if isCanceled {

      task.cancel()

    }

    task.resume()

  }

  func cancel() {

    let task = lock.withLock {

      isCanceled = true

      return self.task

    }

    task?.cancel()

  }

}
#endif
