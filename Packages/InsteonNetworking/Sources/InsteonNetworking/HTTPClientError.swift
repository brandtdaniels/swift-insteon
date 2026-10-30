import Foundation

/// Errors raised by the clients in this module.
///
/// Neither the cases nor their descriptions include a request's credentials or headers.
public enum HTTPClientError: Error, Hashable, Sendable {

  /// The transport returned a response that was not an HTTP response.
  case nonHTTPResponse

  /// An HTTPS request was redirected to an address that isn't HTTPS, so its response isn't
  /// used.
  case insecureRedirect

  /// A request carrying credentials, such as an `Authorization` header, was answered with a
  /// redirect, which wasn't followed.
  ///
  /// Neither the request nor its credentials were sent to the address the redirect named.
  case redirectRefused

}

extension HTTPClientError: CustomStringConvertible, LocalizedError {

  /// A one-line explanation of the error, without credentials or addresses.
  public var description: String {

    switch self {
    case .nonHTTPResponse:
      "The server's answer wasn't an HTTP response."
    case .insecureRedirect:
      "An HTTPS request was redirected to an address that isn't HTTPS, so its answer wasn't used."
    case .redirectRefused:
      "A request carrying credentials was answered with a redirect, so it wasn't sent on to another address."
    }

  }

  /// The same text as the error's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}
