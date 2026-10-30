import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A request to the Hub got no answer after the Hub had answered earlier requests on the same
/// ``HubConnection``.
///
/// The Hub was reachable, so it's busy rather than gone, as when its modem is still sending a
/// message to a device that doesn't answer on a marginal powerline signal. A ``HubConnection``
/// throws this in place of the HTTP client's error for a request that timed out or couldn't
/// reach the Hub, and ``HubStoppedAnswering/underlyingError`` keeps that error. A Hub that
/// hasn't answered any request on the connection, as when its address changed, fails with the
/// HTTP client's error itself.
public struct HubStoppedAnswering: Error, Sendable {

  /// The HTTP client's error, such as a `URLError` whose code is `timedOut`.
  public let underlyingError: any Error

  /// Creates the error.
  ///
  /// - Parameter underlyingError: The HTTP client's error.
  public init(underlyingError: any Error) {

    self.underlyingError = underlyingError

  }

  /// Whether an HTTP client's error means the Hub gave no answer: the request timed out, the
  /// connection was lost or refused, or the host couldn't be found or reached.
  ///
  /// - Parameter error: The error a request to the Hub threw.
  /// - Returns: `true` for a `URLError`, or an error in the URL error domain, with one of those
  ///   codes.
  public static func isUnanswered(_ error: any Error) -> Bool {

    let code: URLError.Code

    if let urlError = error as? URLError {

      code = urlError.code

    } else {

      // swift-corelibs-foundation reports a failed request as an NSError in the URL error
      // domain, which doesn't cast to URLError on Linux.
      let nsError: NSError = error as NSError

      guard nsError.domain == NSURLErrorDomain else {

        return false

      }

      // The initializer is failable on Linux but not on Apple platforms.
      let parsed: URLError.Code? = URLError.Code(rawValue: nsError.code)

      guard let parsed else {

        return false

      }

      code = parsed

    }

    switch code {
    case .timedOut, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost:
      return true
    default:
      return false
    }

  }

}
