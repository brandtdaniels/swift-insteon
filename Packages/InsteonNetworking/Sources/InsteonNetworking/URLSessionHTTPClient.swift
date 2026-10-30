import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Adapts `URLSession` to ``HTTPClient``.
///
/// ## Redirects
///
/// A request that carries credentials is never redirected. When the server answers it with a
/// redirect, the client doesn't follow it and throws ``HTTPClientError/redirectRefused``, so
/// the credentials go only to the address the request named. A request carries credentials
/// when it has an `Authorization` header, as ``BasicAuthenticationHTTPClient`` adds, when the
/// session's configuration adds one to every request, or when its URL includes a user name or
/// password. A Hub never redirects its own requests, so refusing costs a Hub nothing.
///
/// Other requests follow redirects as the session does, except that an HTTPS request that
/// ends at an address that isn't HTTPS throws ``HTTPClientError/insecureRedirect``.
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
  /// - Throws: The session's error if the request failed,
  ///   ``HTTPClientError/nonHTTPResponse`` if the response wasn't HTTP,
  ///   ``HTTPClientError/redirectRefused`` if the request carried credentials and was
  ///   answered with a redirect, or ``HTTPClientError/insecureRedirect`` if an HTTPS request
  ///   ended at an address that isn't HTTPS.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    // A request with credentials gets a delegate that refuses every redirect, so the session
    // never sends the credentials on to another address.
    let refusal: RedirectRefusal? = Self.carriesCredentials(request, configuration: session.configuration) ? RedirectRefusal() : nil

    let (data, response) = try await data(for: request, refusingRedirectsWith: refusal)

    // When a redirect is refused, the session returns the redirect itself as the response.
    if let refusal, refusal.refusedRedirect {

      throw HTTPClientError.redirectRefused

    }

    guard let httpResponse = response as? HTTPURLResponse else {

      throw HTTPClientError.nonHTTPResponse

    }

    // If the delegate wasn't consulted, the request still never counts as answered by a
    // redirect: a redirect status, or a response from another origin, is refused.
    if refusal != nil, Self.isRedirect(httpResponse, for: request) {

      throw HTTPClientError.redirectRefused

    }

    // The session follows redirects on its own, so check where an HTTPS request ended up.
    if request.url?.scheme == "https", httpResponse.url?.scheme != "https" {

      throw HTTPClientError.insecureRedirect

    }

    var headers: [String: String] = [:]

    for case let (name as String, value as String) in httpResponse.allHeaderFields {

      headers[name] = value

    }

    return HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)

  }

  /// Whether a request carries credentials, and so mustn't follow a redirect.
  ///
  /// - Parameters:
  ///   - request: The request to send.
  ///   - configuration: The configuration of the session that sends it, whose additional
  ///     headers are added to every request.
  /// - Returns: `true` if the request or the session adds an `Authorization` header, or the
  ///   request's URL includes a user name or password.
  static func carriesCredentials(_ request: URLRequest, configuration: URLSessionConfiguration) -> Bool {

    if request.value(forHTTPHeaderField: "Authorization") != nil {

      return true

    }

    if request.url?.user != nil || request.url?.password != nil {

      return true

    }

    let additionalHeaders: [AnyHashable: Any] = configuration.httpAdditionalHeaders ?? [:]

    return additionalHeaders.keys.contains { (key: AnyHashable) -> Bool in

      (key.base as? String)?.lowercased() == "authorization"

    }

  }

  /// Whether a response shows that a request was answered by a redirect.
  ///
  /// The delegate refuses a redirect before it's followed. This check backs it up after the
  /// response arrives, so a redirect the delegate wasn't asked about still fails the request.
  ///
  /// - Parameters:
  ///   - response: The response the session returned.
  ///   - request: The request that was sent.
  /// - Returns: `true` if the status is a redirect (300–399), or the response came from a
  ///   different scheme, host or port than the request was sent to.
  static func isRedirect(_ response: HTTPURLResponse, for request: URLRequest) -> Bool {

    if (300...399).contains(response.statusCode) {

      return true

    }

    guard let sent: URL = request.url, let answered: URL = response.url else {

      return false

    }

    return sent.scheme?.lowercased() != answered.scheme?.lowercased()
      || sent.host?.lowercased() != answered.host?.lowercased()
      || sent.port != answered.port

  }

  private func data(for request: URLRequest, refusingRedirectsWith refusal: RedirectRefusal?) async throws -> (Data, URLResponse) {

    #if canImport(FoundationNetworking)
    // swift-corelibs-foundation's async API doesn't ask its delegate about redirects, so bridge
    // the completion handler, and cancel the data task when the calling task is canceled, as
    // the async API on Apple platforms does.
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

        // swift-corelibs-foundation asks the task's own delegate about redirects; it must be
        // set before the task starts.
        if let refusal {

          task.delegate = refusal

        }

        cancellation.start(task)

      }

    } onCancel: {

      cancellation.cancel()

    }
    #else
    if let refusal {

      return try await session.data(for: request, delegate: refusal)

    }

    return try await session.data(for: request)
    #endif

  }

}

/// A task delegate that refuses every redirect and records that it did.
///
/// The session asks it before following a redirect; it answers `nil`, so the session returns
/// the redirect itself as the response and never sends the request to the address it named.
final class RedirectRefusal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

  // `lock` guards `refused`.
  private let lock = NSLock()

  private var refused = false

  /// Whether a redirect was refused.
  var refusedRedirect: Bool {

    lock.withLock { refused }

  }

  /// Records a redirect and refuses it.
  ///
  /// - Parameter request: The request the redirect would send.
  /// - Returns: `nil`, so the redirect isn't followed.
  func refuse(_ request: URLRequest) -> URLRequest? {

    lock.withLock { refused = true }

    return nil

  }

  #if canImport(FoundationNetworking)
  /// Refuses a redirect, so the session returns the redirect itself as the response.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @Sendable @escaping (URLRequest?) -> Void
  ) {

    completionHandler(refuse(request))

  }
  #else
  /// Refuses a redirect, so the session returns the redirect itself as the response.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {

    return refuse(request)

  }
  #endif

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
