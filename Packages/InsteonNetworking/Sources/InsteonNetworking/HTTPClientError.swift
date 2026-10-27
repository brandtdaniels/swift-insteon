/// Errors raised by the clients in this module.
public enum HTTPClientError: Error, Hashable, Sendable {

  /// The transport returned a response that was not an HTTP response.
  case nonHTTPResponse

}
