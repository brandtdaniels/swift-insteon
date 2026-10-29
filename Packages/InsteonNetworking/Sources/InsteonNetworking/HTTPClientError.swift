/// Errors raised by the clients in this module.
public enum HTTPClientError: Error, Hashable, Sendable {

  /// The transport returned a response that was not an HTTP response.
  case nonHTTPResponse

  /// An HTTPS request was redirected to an address that isn't HTTPS, so its response isn't
  /// used.
  case insecureRedirect

}
