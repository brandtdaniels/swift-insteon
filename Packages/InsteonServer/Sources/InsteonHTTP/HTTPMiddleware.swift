import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonService
import Logging

struct AuthenticationMiddleware<Context: RequestContext>: RouterMiddleware {
  let authentication: any HTTPAuthenticating
  let clients: any ClientStoring

  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    let header = request.headers[.authorization]
    let operation = APIOperation(method: request.method, template: context.endpointPath)
    guard let principal = await principal(for: header, operation: operation) else {
      throw AuthenticationFailure(challenge: authentication.challenge, presentedCredentials: header != nil)
    }
    if let operation, !principal.scope.allows(operation.requiredScope) { throw ScopeRefusal() }
    return try await RequestPrincipal.$current.withValue(principal) { try await next(request, context) }
  }

  /// A client token if the header is a Bearer one, otherwise the gateway password acting as `admin`.
  private func principal(for header: String?, operation: APIOperation?) async -> RequestPrincipal? {
    if let token = BearerToken(header) {
      guard operation?.acceptsClientTokens ?? true, let client = await clients.authenticate(token: token.value) else { return nil }
      return RequestPrincipal(scope: client.scope, clientID: client.id)
    }
    return authentication.authorizes(header) ? RequestPrincipal(scope: .admin, clientID: nil) : nil
  }
}

/// Who made the request and what they may do, for the handler that runs for it.
struct RequestPrincipal: Sendable {
  let scope: ClientScope
  /// The client, or `nil` for the gateway password.
  let clientID: String?
  @TaskLocal static var current: RequestPrincipal?
}

/// A `Bearer` Authorization header and the token it carries.
struct BearerToken {
  let value: String
  init?(_ header: String?) {
    guard let header, header.utf8.count <= 4096 else { return nil }
    let parts = header.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count >= 1, parts[0].lowercased() == "bearer" else { return nil }
    // A header that has a scheme but no usable token is a Bearer attempt that fails.
    value = parts.count == 2 ? String(parts[1]) : ""
  }
}

/// A request whose credential is valid but whose scope doesn't allow the operation.
struct ScopeRefusal: Error {}

/// A request that the authentication policy refused, turned into a 401 by ``ErrorMappingMiddleware``.
struct AuthenticationFailure: Error {
  let challenge: String
  /// Whether the request carried an Authorization header, so a browser's first visit differs from a wrong password.
  let presentedCredentials: Bool
}

struct SecurityHeadersMiddleware<Context: RequestContext>: RouterMiddleware {
  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    var response = try await next(request, context)
    response.headers[.cacheControl] = "no-store"
    response.headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
    response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
    response.headers[HTTPField.Name("Content-Security-Policy")!] = "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
    return response
  }
}

struct RequestBodyLimitMiddleware<Context: RequestContext>: RouterMiddleware {
  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    var request = request
    request.body = .init(buffer: try await request.body.collect(upTo: HTTPBody.limit))
    return try await next(request, context)
  }
}

struct ErrorMappingMiddleware<Context: RequestContext>: RouterMiddleware {
  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    do { return try await next(request, context) }
    catch let failure as AuthenticationFailure {
      let code: APIErrorCode = failure.presentedCredentials ? .authenticationFailed : .authenticationRequired
      var response = Self.response(HTTPFailure(code), request, context)
      response.headers[.wwwAuthenticate] = failure.challenge
      return response
    }
    catch {
      var response = Self.response(HTTPFailure(error), request, context)
      if (error as? OutcomeFailure)?.replayed == true { response.headers[.idempotentReplay] = "true" }
      return response
    }
  }


  /// An API route answers with the typed JSON error; the browser's own routes answer with plain text.
  private static func response(_ failure: HTTPFailure, _ request: Request, _ context: Context) -> Response {
    guard request.uri.path.hasPrefix("/api/") else {
      return Response(status: failure.status, headers: [.contentType: "text/plain; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: failure.message)))
    }
    let body = (try? JSONEncoder().encode(ErrorDTO(failure, requestID: "\(context.id)"))) ?? Data()
    return Response(status: failure.status, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: body)))
  }
}

/// What a thrown error means to a client and to the log: the code, the status and message the
/// client sees, whether a command may have reached a device, and for a failed operation a
/// credential-free cause.
struct HTTPFailure: Sendable {
  let code: APIErrorCode
  let status: HTTPResponse.Status
  let message: String
  let sent: Bool
  let cause: String?
  /// Set when the modem is away, so the response can say why in a body clients can branch on.
  let modemUnavailability: ModemUnavailability?

  init(_ code: APIErrorCode) {
    self.init(code, status: code.status)
  }

  init(_ code: APIErrorCode, sent: Bool) {
    self.init(code, status: code.status, sent: sent)
  }

  init(_ error: any Error) {
    if let outcome = error as? OutcomeFailure {
      self = outcome.failure
    } else if let failure = error as? CommandFailure {
      self.init(classifying: failure.underlying, action: failure.action)
    } else {
      self.init(classifying: error, action: nil)
    }
  }

  /// - Parameter action: What the failed command asked for. A read changes nothing, so its failure
  ///   is safe to repeat; an unknown action is treated as a control.
  private init(classifying error: any Error, action: ServiceCommand.Action?) {
    let isRead = action == .status || action == .identify
    switch error {
    case let ServiceControlError.modemUnavailable(unavailable):
      self.init(.modemUnavailable, message: unavailable.refusal, modemUnavailability: unavailable)
    case ServiceControlError.busy: self.init(.busy)
    case ServiceControlError.unknownDevice: self.init(.unknownDevice)
    case ServiceControlError.invalidLevel: self.init(.invalidLevel)
    case ServiceControlError.unsupportedControl: self.init(.unsupportedControl)
    case ServiceControlError.notIdentified: self.init(.notIdentified)
    case ServiceControlError.notLinked: self.init(.notLinked)
    case is ScopeRefusal: self.init(.forbidden)
    case ClientError.invalidName, is ClientRequestError: self.init(.invalidClient)
    case ClientError.unknownClient: self.init(.unknownClient)
    case ClientError.limitReached: self.init(.clientLimitReached)
    case ClientError.notSaved: self.init(.clientsNotSaved)
    case NotificationRuleError.invalidRule, is NotificationRuleRequestError: self.init(.invalidNotificationRule)
    case NotificationRuleError.unknownDevice: self.init(.unknownDevice)
    case NotificationRuleError.unknownRule: self.init(.unknownNotificationRule)
    case NotificationRuleError.limitReached: self.init(.notificationRuleLimitReached)
    case NotificationRuleError.notSaved: self.init(.notificationRulesNotSaved)
    case RouteError.invalidRoute: self.init(.invalidRouteRegistration)
    case RouteError.unknownRoute: self.init(.unknownRouteRegistration)
    case RouteError.limitReached: self.init(.routeRegistrationLimitReached)
    case RouteError.notSaved: self.init(.routeRegistrationsNotSaved)
    case HTTPInputError.unsupportedMedia: self.init(.unsupportedMediaType)
    case HTTPInputError.missingAPIMarker: self.init(.apiMarkerMissing)
    case HTTPInputError.invalidFormKey: self.init(.formKeyInvalid)
    case HTTPInputError.invalidAddress: self.init(.invalidAddress)
    case IdempotencyError.invalidKey: self.init(.invalidIdempotencyKey)
    case IdempotencyError.reused: self.init(.idempotencyKeyReused)
    case is HTTPInputError: self.init(.invalidCommand)
    case is DecodingError: self.init(.invalidCommand)
    case let error as any HTTPResponseError:
      switch error.status {
      case .contentTooLarge: self.init(.bodyTooLarge)
      case .notFound: self.init(.routeNotFound)
      default: self.init(.requestRejected, status: error.status)
      }
    case is CancellationError:
      self.init(.canceled, sent: !isRead)
    default:
      // A library error's description never carries credentials. Any other error is named by type only,
      // because its description can carry request details.
      let cause = InsteonErrorDescription.message(for: error) ?? "unclassified \(type(of: error))"
      switch error {
      case let HubError.unexpectedStatus(status) where status == 401 || status == 403:
        // The Hub refused the request before it reached the modem.
        self.init(.modemUnavailable, message: ModemUnavailability.credentialsRejected.refusal, cause: cause, modemUnavailability: .credentialsRejected)
      case let ModemError.deviceRejected(_, reason) where reason == .notLinked:
        self.init(.notLinked, cause: cause)
      case DeviceControlError.notLinked: self.init(.notLinked, cause: cause)
      case DeviceControlError.notIdentified: self.init(.notIdentified, cause: cause)
      case is DeviceControlError: self.init(.unsupportedControl, cause: cause)
      case ModemError.deviceRejected: self.init(.deviceRejected, cause: cause)
      case ModemError.rejected: self.init(.modemRejected, cause: cause)
      default: self.init(isRead ? .deviceNotAnswering : .outcomeUnknown, cause: cause)
      }
    }
  }

  private init(_ code: APIErrorCode, status: HTTPResponse.Status? = nil, message: String? = nil, sent: Bool? = nil, cause: String? = nil, modemUnavailability: ModemUnavailability? = nil) {
    self.code = code
    self.status = status ?? code.status
    self.message = message ?? code.message
    self.sent = sent ?? code.sent
    self.cause = cause
    self.modemUnavailability = modemUnavailability
  }
}

/// Logs one record per request: its method, route template, status, duration and a stable outcome code.
///
/// The record never carries the request's path, query, headers or body, because they hold what a
/// client chose to send, including passwords. A route is the template it matched, such as
/// `/api/v1/devices/{address}/commands`, or `unmatched`. A method outside the ones the server
/// routes is `other`.
struct RequestLogMiddleware<Context: RequestContext>: RouterMiddleware {
  let logger: Logger
  private static var knownMethods: Set<String> { ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"] }

  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    let start = ContinuousClock.now
    let outcome: Outcome
    do {
      let response = try await next(request, context)
      outcome = Outcome(status: response.status, code: response.status.code < 400 ? "ok" : "errorResponse", level: Self.level(for: response.status), cause: nil)
      log(outcome, request, context, since: start)
      return response
    } catch let failure as AuthenticationFailure {
      outcome = Outcome(
        status: .unauthorized,
        code: (failure.presentedCredentials ? APIErrorCode.authenticationFailed : .authenticationRequired).rawValue,
        level: failure.presentedCredentials ? .warning : .info,
        cause: nil
      )
      log(outcome, request, context, since: start)
      throw failure
    } catch {
      let failure = HTTPFailure(error)
      outcome = Outcome(status: failure.status, code: failure.code.rawValue, level: Self.level(for: failure.status), cause: failure.cause)
      log(outcome, request, context, since: start)
      throw error
    }
  }

  private struct Outcome {
    let status: HTTPResponse.Status
    let code: String
    let level: Logger.Level
    let cause: String?
  }

  private static func level(for status: HTTPResponse.Status) -> Logger.Level {
    status.code >= 500 ? .error : status.code >= 400 ? .warning : .info
  }

  private func log(_ outcome: Outcome, _ request: Request, _ context: Context, since start: ContinuousClock.Instant) {
    let elapsed = start.duration(to: .now)
    let milliseconds = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
    let method = request.method.rawValue
    // Hummingbird names its fallback for an unknown path "NotFound"; only a registered template starts with a slash.
    let route = context.endpointPath.flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "unmatched"
    var metadata: Logger.Metadata = [
      "request_id": "\(context.id)",
      "method": "\(Self.knownMethods.contains(method) ? method : "other")",
      "route": "\(route)",
      "status": "\(outcome.status.code)",
      "duration_ms": "\(milliseconds)",
      "code": "\(outcome.code)"
    ]
    if let cause = outcome.cause { metadata["cause"] = "\(cause)" }
    logger.log(level: outcome.level, "request", metadata: metadata)
  }
}
