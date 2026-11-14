import Hummingbird
import HTTPTypes
import InsteonService

struct AuthenticationMiddleware<Context: RequestContext>: RouterMiddleware {
  let authentication: any HTTPAuthenticating
  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    guard authentication.authorizes(request.headers[.authorization]) else {
      return Response(status: .unauthorized, headers: [.wwwAuthenticate: authentication.challenge], body: .init(byteBuffer: ByteBuffer(string: "Authentication required.")))
    }
    return try await next(request, context)
  }
}

struct SecurityHeadersMiddleware<Context: RequestContext>: RouterMiddleware {
  func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
    var response = try await next(request, context)
    response.headers[.cacheControl] = "no-store"
    response.headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
    response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
    response.headers[HTTPField.Name("Content-Security-Policy")!] = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
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
    catch ServiceControlError.busy { return text(.conflict, "The service is busy. Try again explicitly; nothing was queued.") }
    catch ServiceControlError.unknownDevice { return text(.notFound, "Unknown device.") }
    catch ServiceControlError.invalidLevel { return text(.badRequest, "The device or action does not accept that percentage.") }
    catch ServiceControlError.unsupportedControl { return text(.unprocessableContent, "The device does not support that control.") }
    catch HTTPInputError.unsupportedMedia { return text(.unsupportedMediaType, "Unsupported content type.") }
    catch HTTPInputError.missingAPIMarker { return text(.forbidden, "An explicit API request is required.") }
    catch HTTPInputError.invalidFormKey { return text(.forbidden, "The form expired. Reload the page and try again.") }
    catch is HTTPInputError { return text(.badRequest, "Invalid command or form.") }
    catch is DecodingError { return text(.badRequest, "Invalid command.") }
    catch let error as any HTTPResponseError {
      return text(error.status, error.status == .contentTooLarge ? "Request body too large." : "Invalid request.")
    }
    catch is CancellationError { return text(.serviceUnavailable, "Request canceled. Its hardware outcome may be unknown; read status before retrying.") }
    catch { return text(.badGateway, "Operation failed. Its hardware outcome may be unknown; read status before retrying.") }
  }

  private func text(_ status: HTTPResponse.Status, _ message: String) -> Response {
    Response(status: status, headers: [.contentType: "text/plain; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(string: message)))
  }
}
