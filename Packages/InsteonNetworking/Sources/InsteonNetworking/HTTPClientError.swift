import Foundation

/// Errors raised by the clients in this module.
///
/// Neither the cases nor their descriptions include a request's credentials or headers.
public enum HTTPClientError: Error, Hashable, Sendable {

  /// The transport returned a response that was not an HTTP response.
  case nonHTTPResponse

  /// An HTTPS request was redirected to an address that isn't HTTPS, so its response isn't
  /// used.
  ///
  /// Under ``RedirectPolicy/sameOriginHTTPSOnly``, the redirect wasn't followed, so the request
  /// wasn't sent to that address.
  case insecureRedirect

  /// A request was answered with a redirect its redirect policy doesn't follow, so the
  /// redirect wasn't followed.
  ///
  /// A request carrying credentials, such as an `Authorization` header, follows no redirects.
  /// A request under ``RedirectPolicy/sameOriginHTTPSOnly`` follows none to another host or
  /// port. Neither the request nor its credentials were sent to the address the redirect
  /// named.
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
      "A request was answered with a redirect that isn't followed, so it wasn't sent on to another address."
    }

  }

  /// The same text as the error's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}
