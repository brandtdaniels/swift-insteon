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
/// Other requests follow redirects as ``URLSessionHTTPClient/redirectPolicy`` allows. With
/// the default, ``RedirectPolicy/followAll``, they follow redirects as the session does,
/// except that an HTTPS request that ends at an address that isn't HTTPS throws
/// ``HTTPClientError/insecureRedirect``. That check runs after the response arrives, when the
/// session has already sent the request to every address in between. With
/// ``RedirectPolicy/sameOriginHTTPSOnly``, the client decides before following each redirect,
/// and follows it only to HTTPS at the request's own host and port.
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {

  // `URLSession` is thread-safe; it isn't marked `Sendable` on every platform.
  private let session: URLSession

  /// Which redirects requests without credentials follow.
  ///
  /// Requests with credentials follow none, whatever the policy.
  public let redirectPolicy: RedirectPolicy

  /// Creates a client that sends requests with a session.
  ///
  /// - Parameters:
  ///   - session: The session to send requests with. Defaults to the shared session.
  ///   - redirectPolicy: Which redirects requests without credentials follow. Defaults to
  ///     ``RedirectPolicy/followAll``.
  public init(session: URLSession = .shared, redirectPolicy: RedirectPolicy = .followAll) {

    self.session = session
    self.redirectPolicy = redirectPolicy

  }

  /// Sends a request with the session.
  ///
  /// - Parameter request: The request to send.
  /// - Returns: The response's status, headers and body.
  /// - Throws: The session's error if the request failed,
  ///   ``HTTPClientError/nonHTTPResponse`` if the response wasn't HTTP,
  ///   ``HTTPClientError/redirectRefused`` if the request was answered with a redirect its
  ///   policy doesn't follow, or ``HTTPClientError/insecureRedirect`` if an HTTPS request was
  ///   redirected to, or ended at, an address that isn't HTTPS.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    // A request with credentials refuses every redirect, so the session never sends the
    // credentials on to another address.
    let policy: RedirectPolicy = Self.policy(for: request, configuration: session.configuration, clientPolicy: redirectPolicy)

    // Any policy but following every redirect gets a delegate that decides before the session
    // follows one.
    let refusal: RedirectRefusal? = policy == .followAll ? nil : RedirectRefusal(policy: policy, original: request.url)

    let (data, response) = try await data(for: request, refusingRedirectsWith: refusal)

    // When a redirect is refused, the session returns the redirect itself as the response.
    if let refusal, refusal.refusedRedirect {

      throw Self.error(refusing: refusal.refusedTarget, of: request, policy: policy)

    }

    guard let httpResponse = response as? HTTPURLResponse else {

      throw HTTPClientError.nonHTTPResponse

    }

    // If the delegate wasn't consulted, a request that refuses every redirect still never
    // counts as answered by one: a redirect status, or a response from another origin, is
    // refused.
    if policy == .refuseAll, Self.isRedirect(httpResponse, for: request) {

      throw HTTPClientError.redirectRefused

    }

    // The session follows redirects on its own, so check where an HTTPS request ended up.
    if request.url?.scheme == "https", httpResponse.url?.scheme != "https" {

      throw HTTPClientError.insecureRedirect

    }

    // If the delegate wasn't consulted, a same-origin request still never counts as answered
    // from another origin.
    if policy == .sameOriginHTTPSOnly, Self.isFromAnotherOrigin(httpResponse, for: request) {

      throw HTTPClientError.redirectRefused

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

  /// The redirect policy a request is sent with.
  ///
  /// - Parameters:
  ///   - request: The request to send.
  ///   - configuration: The configuration of the session that sends it.
  ///   - clientPolicy: The client's policy.
  /// - Returns: ``RedirectPolicy/refuseAll`` if the request carries credentials, and the
  ///   client's policy otherwise.
  static func policy(for request: URLRequest, configuration: URLSessionConfiguration, clientPolicy: RedirectPolicy) -> RedirectPolicy {

    carriesCredentials(request, configuration: configuration) ? .refuseAll : clientPolicy

  }

  /// The error for a redirect the delegate refused.
  ///
  /// - Parameters:
  ///   - target: The address the refused redirect named, if known.
  ///   - request: The request that was sent.
  ///   - policy: The policy the request was sent with.
  /// - Returns: ``HTTPClientError/insecureRedirect`` if a same-origin HTTPS request was
  ///   redirected to an address that isn't HTTPS, and ``HTTPClientError/redirectRefused``
  ///   otherwise.
  static func error(refusing target: URL?, of request: URLRequest, policy: RedirectPolicy) -> HTTPClientError {

    let isDowngrade: Bool = request.url?.scheme?.lowercased() == "https" && target?.scheme?.lowercased() != "https"

    return policy == .sameOriginHTTPSOnly && isDowngrade ? .insecureRedirect : .redirectRefused

  }

  /// Whether a response came from a different scheme, host or port than the request was sent
  /// to.
  ///
  /// - Parameters:
  ///   - response: The response the session returned.
  ///   - request: The request that was sent.
  /// - Returns: `true` if both addresses are known and their origins differ.
  static func isFromAnotherOrigin(_ response: HTTPURLResponse, for request: URLRequest) -> Bool {

    guard let sent: URL = request.url, let answered: URL = response.url else {

      return false

    }

    return Origin(sent) != Origin(answered)

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

/// A task delegate that decides, by a redirect policy, whether to follow each redirect, and
/// records a redirect it refuses.
///
/// The session asks it before following a redirect. For a redirect the policy refuses, it
/// answers `nil`, so the session returns the redirect itself as the response and never sends
/// the request to the address it named. Every redirect is compared with the address the
/// request was first sent to, not the one before it, so a chain can't leave and come back.
final class RedirectRefusal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

  /// The policy each redirect is decided by.
  let policy: RedirectPolicy

  /// The address the request was first sent to.
  let original: URL?

  // `lock` guards `refused` and `target`.
  private let lock = NSLock()

  private var refused = false

  private var target: URL?

  /// Creates a delegate that refuses every redirect.
  override convenience init() {

    self.init(policy: .refuseAll, original: nil)

  }

  /// Creates a delegate that decides by a policy.
  ///
  /// - Parameters:
  ///   - policy: The policy each redirect is decided by.
  ///   - original: The address the request is first sent to.
  init(policy: RedirectPolicy, original: URL?) {

    self.policy = policy
    self.original = original

    super.init()

  }

  /// Whether a redirect was refused.
  var refusedRedirect: Bool {

    lock.withLock { refused }

  }

  /// The address the first refused redirect named, or `nil` if none was refused or it named
  /// none.
  var refusedTarget: URL? {

    lock.withLock { target }

  }

  /// Follows a redirect the policy allows, and records and refuses any other.
  ///
  /// After one redirect is refused, every later one is refused too.
  ///
  /// - Parameter request: The request the redirect would send.
  /// - Returns: The request if the redirect is followed, or `nil` if it isn't.
  func decide(_ request: URLRequest) -> URLRequest? {

    let allowed: Bool = policy.allows(redirectTo: request.url, from: original)

    return lock.withLock { () -> URLRequest? in

      if allowed, !refused {

        return request

      }

      if !refused {

        refused = true
        target = request.url

      }

      return nil

    }

  }

  #if canImport(FoundationNetworking)
  /// Follows or refuses a redirect; a refused one is returned as the response.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @Sendable @escaping (URLRequest?) -> Void
  ) {

    completionHandler(decide(request))

  }
  #else
  /// Follows or refuses a redirect; a refused one is returned as the response.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {

    return decide(request)

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
