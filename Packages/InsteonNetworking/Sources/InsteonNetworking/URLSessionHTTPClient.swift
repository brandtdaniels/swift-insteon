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
///
/// ## The local network
///
/// ``URLSessionHTTPClient/localNetwork(maximumResponseSize:resourceTimeout:)`` makes the client
/// for devices on the local network, such as a Hub: its session of its own goes to the device
/// directly, never through a proxy, keeps no cookies, credentials or cache, follows no
/// redirects and reads at most ``URLSessionHTTPClient/localNetworkMaximumResponseSize`` bytes
/// of an answer. A proxy would receive a Hub's credentials, which plain HTTP carries readably.
/// On Apple platforms the session's configuration turns proxies off. On Linux,
/// swift-corelibs-foundation ignores that and libcurl uses the proxy the environment names, so
/// the client refuses a request a proxy would carry and throws
/// ``HTTPClientError/proxyConfigured`` instead; naming the device's exact address in
/// `no_proxy` sends it directly, since an address range there isn't read.
///
/// ## The size of an answer
///
/// A client with a ``URLSessionHTTPClient/maximumResponseSize`` throws
/// ``HTTPClientError/responseTooLarge(limit:)`` for a larger body. On Apple platforms it stops
/// reading once the body passes the limit, or before reading if the body's length says so. On
/// Linux, swift-corelibs-foundation hands over a body only once it's complete, so the body is
/// checked then; a client for the local network also has a time limit for the whole request,
/// which bounds how much can arrive.
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {

  /// The most a client for the local network reads of an answer by default: 64 KiB.
  ///
  /// A Hub's buffer page is well under 1 KiB, and its other pages a few KiB.
  public static let localNetworkMaximumResponseSize: Int = 64 * 1024

  /// How long a request from a client for the local network may take in all by default: 120
  /// seconds.
  ///
  /// This bounds a request whose caller sets no shorter limit; a Hub's own requests stop far
  /// sooner, after `Hub.requestTimeout`.
  public static let localNetworkResourceTimeout: Duration = .seconds(120)

  // `URLSession` is thread-safe; it isn't marked `Sendable` on every platform.
  private let session: URLSession

  /// Which redirects requests without credentials follow.
  ///
  /// Requests with credentials follow none, whatever the policy.
  public let redirectPolicy: RedirectPolicy

  /// The most bytes of an answer's body the client reads, or `nil` for no limit.
  public let maximumResponseSize: Int?

  /// The environment's proxy settings, for a client that refuses a request a proxy would
  /// carry, or `nil` for a client that sends requests as the session does.
  private let proxyEnvironment: ProxyEnvironment?

  /// Whether the client made its session, and so invalidates it when it's released.
  private let ownsSession: Bool

  /// Creates a client that sends requests with a session.
  ///
  /// - Parameters:
  ///   - session: The session to send requests with. Defaults to the shared session.
  ///   - redirectPolicy: Which redirects requests without credentials follow. Defaults to
  ///     ``RedirectPolicy/followAll``.
  ///   - maximumResponseSize: The most bytes of an answer's body to read, or `nil` for no
  ///     limit. Defaults to `nil`.
  public convenience init(session: URLSession = .shared, redirectPolicy: RedirectPolicy = .followAll, maximumResponseSize: Int? = nil) {

    self.init(
      session: session,
      redirectPolicy: redirectPolicy,
      maximumResponseSize: maximumResponseSize,
      proxyEnvironment: nil,
      ownsSession: false
    )

  }

  private init(
    session: URLSession,
    redirectPolicy: RedirectPolicy,
    maximumResponseSize: Int?,
    proxyEnvironment: ProxyEnvironment?,
    ownsSession: Bool
  ) {

    self.session = session
    self.redirectPolicy = redirectPolicy
    self.maximumResponseSize = maximumResponseSize.map { (limit: Int) -> Int in max(0, limit) }
    self.proxyEnvironment = proxyEnvironment
    self.ownsSession = ownsSession

  }

  deinit {

    if ownsSession {

      session.finishTasksAndInvalidate()

    }

  }

  /// Makes a client for devices on the local network, such as a Hub, with a session of its
  /// own.
  ///
  /// The session sends each request to the device directly, never through a proxy, keeps no
  /// cookies, credentials or cache, and follows no redirects, which a device on the local
  /// network never sends. On Linux, where the environment's proxy can't be turned off, a
  /// request a proxy would carry is refused with ``HTTPClientError/proxyConfigured``.
  ///
  /// ```swift
  /// let hub = Hub(endpoint: endpoint, user: user, password: password, httpClient: URLSessionHTTPClient.localNetwork())
  /// ```
  ///
  /// - Parameters:
  ///   - maximumResponseSize: The most bytes of an answer's body to read. Defaults to
  ///     ``URLSessionHTTPClient/localNetworkMaximumResponseSize``.
  ///   - resourceTimeout: How long a request may take in all. Defaults to
  ///     ``URLSessionHTTPClient/localNetworkResourceTimeout``.
  /// - Returns: The client.
  public static func localNetwork(
    maximumResponseSize: Int = URLSessionHTTPClient.localNetworkMaximumResponseSize,
    resourceTimeout: Duration = URLSessionHTTPClient.localNetworkResourceTimeout
  ) -> URLSessionHTTPClient {

    localNetwork(maximumResponseSize: maximumResponseSize, resourceTimeout: resourceTimeout, environment: ProcessInfo.processInfo.environment)

  }

  /// Makes a client for devices on the local network that reads its proxy settings from an
  /// environment, for tests.
  package static func localNetwork(maximumResponseSize: Int, resourceTimeout: Duration, environment: [String: String]) -> URLSessionHTTPClient {

    URLSessionHTTPClient(
      session: URLSession(configuration: isolatedConfiguration(resourceTimeout: resourceTimeout, turningProxiesOff: true)),
      redirectPolicy: .refuseAll,
      maximumResponseSize: maximumResponseSize,
      proxyEnvironment: ProxyEnvironment(environment),
      ownsSession: true
    )

  }

  /// Makes a client with a session of its own that keeps nothing between requests, for a
  /// request that shouldn't leave a trace on the device, such as one to Insteon's servers.
  ///
  /// The session keeps no cookies, credentials or cache. It uses the proxy the system or the
  /// environment sets, as other requests do, so it reaches the internet where only a proxy
  /// can; for an HTTPS request, a proxy carries only an encrypted tunnel to the host. Send no
  /// credentials through it to a plain HTTP address: use
  /// ``URLSessionHTTPClient/localNetwork(maximumResponseSize:resourceTimeout:)`` for devices
  /// on the local network.
  ///
  /// - Parameters:
  ///   - redirectPolicy: Which redirects requests without credentials follow.
  ///   - maximumResponseSize: The most bytes of an answer's body to read.
  ///   - resourceTimeout: How long a request may take in all.
  /// - Returns: The client.
  public static func ephemeral(redirectPolicy: RedirectPolicy, maximumResponseSize: Int, resourceTimeout: Duration) -> URLSessionHTTPClient {

    URLSessionHTTPClient(
      session: URLSession(configuration: isolatedConfiguration(resourceTimeout: resourceTimeout, turningProxiesOff: false)),
      redirectPolicy: redirectPolicy,
      maximumResponseSize: maximumResponseSize,
      proxyEnvironment: nil,
      ownsSession: true
    )

  }

  /// The proxy settings that turn every proxy off, in the keys of CFNetwork's proxy
  /// dictionary: HTTP, HTTPS, SOCKS and automatic configuration, each `0`.
  ///
  /// The keys are written out because CFNetwork names some of them only on macOS. Linux
  /// ignores the dictionary.
  package static let noProxies: [String: Int] = [
    "HTTPEnable": 0,
    "HTTPSEnable": 0,
    "SOCKSEnable": 0,
    "ProxyAutoConfigEnable": 0,
    "ProxyAutoDiscoveryEnable": 0,
  ]

  /// A configuration that keeps no cookies, credentials or cache and limits a request's total
  /// time.
  ///
  /// - Parameters:
  ///   - resourceTimeout: How long a request may take in all.
  ///   - turningProxiesOff: Whether to turn every proxy off, where the platform reads the
  ///     setting, or to use the system's.
  /// - Returns: The configuration.
  package static func isolatedConfiguration(resourceTimeout: Duration, turningProxiesOff: Bool) -> URLSessionConfiguration {

    let configuration: URLSessionConfiguration = URLSessionConfiguration.ephemeral

    if turningProxiesOff {

      configuration.connectionProxyDictionary = noProxies as [AnyHashable: Any]

    }

    configuration.urlCredentialStorage = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForResource = seconds(resourceTimeout)

    return configuration

  }

  /// The configuration of the client's session, for tests.
  package var sessionConfiguration: URLSessionConfiguration {

    session.configuration

  }

  /// Whether the session adds an `Authorization` header to every request it sends.
  var sessionAddsCredentials: Bool {

    Self.addsCredentials(session.configuration)

  }

  /// Whether the session has a credential storage, whose saved credentials it could answer a
  /// server's challenge with.
  var sessionStoresCredentials: Bool {

    session.configuration.urlCredentialStorage != nil

  }

  /// A duration in seconds, as `URLSessionConfiguration` takes it.
  private static func seconds(_ duration: Duration) -> TimeInterval {

    let (seconds, attoseconds) = duration.components

    return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18

  }

  /// Sends a request with the session.
  ///
  /// - Parameter request: The request to send.
  /// - Returns: The response's status, headers and body.
  /// - Throws: The session's error if the request failed,
  ///   ``HTTPClientError/nonHTTPResponse`` if the response wasn't HTTP,
  ///   ``HTTPClientError/redirectRefused`` if the request was answered with a redirect its
  ///   policy doesn't follow, ``HTTPClientError/insecureRedirect`` if an HTTPS request was
  ///   redirected to, or ended at, an address that isn't HTTPS,
  ///   ``HTTPClientError/responseTooLarge(limit:)`` if the body is larger than
  ///   ``URLSessionHTTPClient/maximumResponseSize``, or ``HTTPClientError/proxyConfigured`` if
  ///   a client for the local network would send the request through a proxy.
  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    #if canImport(FoundationNetworking)
    // libcurl reads its proxy from the environment, and nothing turns it off, so a request it
    // would send through one isn't sent at all.
    if let proxyEnvironment, proxyEnvironment.proxies(request.url) {

      throw HTTPClientError.proxyConfigured

    }
    #endif

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

    return addsCredentials(configuration)

  }

  /// Whether a session's configuration adds an `Authorization` header to every request.
  ///
  /// - Parameter configuration: The session's configuration.
  /// - Returns: `true` if its additional headers include `Authorization`, in any case.
  static func addsCredentials(_ configuration: URLSessionConfiguration) -> Bool {

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

  #if !canImport(FoundationNetworking)
  /// Reads a response's body as it arrives, and stops once it passes a limit.
  ///
  /// - Parameters:
  ///   - request: The request to send.
  ///   - delegate: The task's delegate, if it has one.
  ///   - limit: The most bytes of the body to read.
  /// - Returns: The body and the response.
  /// - Throws: ``HTTPClientError/responseTooLarge(limit:)`` if the body's length, as the
  ///   response gives it or as it arrives, is larger than the limit, or the session's error.
  private func boundedData(for request: URLRequest, delegate: RedirectRefusal?, limit: Int) async throws -> (Data, URLResponse) {

    let (bytes, response): (URLSession.AsyncBytes, URLResponse) = try await session.bytes(for: request, delegate: delegate)

    // The length the response gives decides before any of the body is read.
    if response.expectedContentLength > Int64(limit) {

      bytes.task.cancel()

      throw HTTPClientError.responseTooLarge(limit: limit)

    }

    var data: Data = Data()

    if response.expectedContentLength > 0 {

      data.reserveCapacity(Int(response.expectedContentLength))

    }

    for try await byte in bytes {

      guard data.count < limit else {

        bytes.task.cancel()

        throw HTTPClientError.responseTooLarge(limit: limit)

      }

      data.append(byte)

    }

    return (data, response)

  }
  #endif

  private func data(for request: URLRequest, refusingRedirectsWith refusal: RedirectRefusal?) async throws -> (Data, URLResponse) {

    #if canImport(FoundationNetworking)
    // swift-corelibs-foundation's async API doesn't ask its delegate about redirects, so bridge
    // the completion handler, and cancel the data task when the calling task is canceled, as
    // the async API on Apple platforms does.
    let cancellation = DataTaskCancellation()

    let (body, answer): (Data, URLResponse) = try await withTaskCancellationHandler {

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

    // The body arrives whole, so its size can only be checked now.
    if let maximumResponseSize, body.count > maximumResponseSize {

      throw HTTPClientError.responseTooLarge(limit: maximumResponseSize)

    }

    return (body, answer)
    #else
    if let maximumResponseSize {

      return try await boundedData(for: request, delegate: refusal, limit: maximumResponseSize)

    }

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
