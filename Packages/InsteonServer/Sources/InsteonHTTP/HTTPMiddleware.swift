import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonService
import Logging

struct AuthenticationMiddleware<Context: RequestContext>: RouterMiddleware {
  let authentication: any HTTPAuthenticating
  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    let header = request.headers[.authorization]
    guard authentication.authorizes(header) else {
      throw AuthenticationFailure(challenge: authentication.challenge, presentedCredentials: header != nil)
    }
    return try await next(request, context)
  }
}

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
      return Response(status: .unauthorized, headers: [.wwwAuthenticate: failure.challenge], body: .init(byteBuffer: ByteBuffer(string: "Authentication required.")))
    }
    catch {
      let failure = HTTPFailure(error)
      if let unavailable = failure.modemUnavailability {
        // A machine-readable refusal: nothing was sent, and the cause says why.
        let body = (try? JSONEncoder().encode(ModemUnavailableDTO(unavailable))) ?? Data()
        return Response(status: failure.status, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: body)))
      }
      return Response(status: failure.status, headers: [.contentType: "text/plain; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: failure.message)))
    }
  }
}

/// What a thrown error means to a client and to the log: the status and message the client
/// sees, a stable code for the log, and for a failed operation a credential-free cause.
struct HTTPFailure {
  let status: HTTPResponse.Status
  let message: String
  let code: String
  let cause: String?
  /// Set when the modem is away, so the response can say why in a body clients can branch on.
  let modemUnavailability: ModemUnavailability?

  init(_ error: any Error) {
    switch error {
    case let ServiceControlError.modemUnavailable(unavailable):
      self.init(.serviceUnavailable, unavailable.refusal, "modem_unavailable", modemUnavailability: unavailable)
    case ServiceControlError.busy: self.init(.conflict, "The service is busy. Try again explicitly; nothing was queued.", "busy")
    case ServiceControlError.unknownDevice: self.init(.notFound, "Unknown device.", "unknown_device")
    case ServiceControlError.invalidLevel: self.init(.badRequest, "The device or action does not accept that percentage.", "invalid_level")
    case ServiceControlError.unsupportedControl: self.init(.unprocessableContent, "The device does not support that control.", "unsupported_control")
    case HTTPInputError.unsupportedMedia: self.init(.unsupportedMediaType, "Unsupported content type.", "unsupported_media")
    case HTTPInputError.missingAPIMarker: self.init(.forbidden, "An explicit API request is required.", "api_marker_missing")
    case HTTPInputError.invalidFormKey: self.init(.forbidden, "The form expired. Reload the page and try again.", "form_key_invalid")
    case is HTTPInputError: self.init(.badRequest, "Invalid command or form.", "input_invalid")
    case is DecodingError: self.init(.badRequest, "Invalid command.", "command_invalid")
    case let error as any HTTPResponseError:
      let tooLarge = error.status == .contentTooLarge
      self.init(error.status, tooLarge ? "Request body too large." : "Invalid request.", tooLarge ? "body_too_large" : "request_rejected")
    case is CancellationError:
      self.init(.serviceUnavailable, "Request canceled. Its hardware outcome may be unknown; read status before retrying.", "canceled")
    default:
      // A library error's description never carries credentials. Any other error is named by type only,
      // because its description can carry request details.
      let cause = InsteonErrorDescription.message(for: error) ?? "unclassified \(type(of: error))"
      self.init(.badGateway, "Operation failed. Its hardware outcome may be unknown; read status before retrying.", "operation_failed", cause: cause)
    }
  }

  private init(_ status: HTTPResponse.Status, _ message: String, _ code: String, cause: String? = nil, modemUnavailability: ModemUnavailability? = nil) {
    self.modemUnavailability = modemUnavailability
    self.status = status
    self.message = message
    self.code = code
    self.cause = cause
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
      outcome = Outcome(status: response.status, code: response.status.code < 400 ? "ok" : "error_response", level: Self.level(for: response.status), cause: nil)
      log(outcome, request, context, since: start)
      return response
    } catch let failure as AuthenticationFailure {
      outcome = Outcome(
        status: .unauthorized,
        code: failure.presentedCredentials ? "authentication_failed" : "authentication_required",
        level: failure.presentedCredentials ? .warning : .info,
        cause: nil
      )
      log(outcome, request, context, since: start)
      throw failure
    } catch {
      let failure = HTTPFailure(error)
      outcome = Outcome(status: failure.status, code: failure.code, level: Self.level(for: failure.status), cause: failure.cause)
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
