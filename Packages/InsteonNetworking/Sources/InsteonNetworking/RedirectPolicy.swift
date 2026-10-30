import Foundation

/// Which redirects ``URLSessionHTTPClient`` follows.
///
/// The client decides before it follows each redirect, so a request is never sent to an
/// address the policy refuses. A request that carries credentials refuses every redirect,
/// whatever the client's policy.
public struct RedirectPolicy: Hashable, Sendable {

  enum Kind: Hashable, Sendable {

    case followAll

    case sameOriginHTTPSOnly

    case refuseAll

  }

  let kind: Kind

  private init(_ kind: Kind) {

    self.kind = kind

  }

  /// Follows every redirect the session follows.
  ///
  /// An HTTPS request that ends at an address that isn't HTTPS still throws
  /// ``HTTPClientError/insecureRedirect``, but only after the session has sent the request on
  /// to each address in between.
  public static let followAll: RedirectPolicy = RedirectPolicy(.followAll)

  /// Follows a redirect only to an HTTPS address with the same host and port as the request.
  ///
  /// A redirect from HTTPS to an address that isn't HTTPS throws
  /// ``HTTPClientError/insecureRedirect``, and a redirect to another host or port throws
  /// ``HTTPClientError/redirectRefused``. Neither is followed, so a chain that leaves HTTPS
  /// and comes back to another host is refused at its first step. A request that isn't HTTPS
  /// follows no redirects. A redirect to the same address with a trailing slash, or to
  /// another path on the same host, is followed.
  ///
  /// Use it for a download whose integrity rests on HTTPS to the expected host.
  public static let sameOriginHTTPSOnly: RedirectPolicy = RedirectPolicy(.sameOriginHTTPSOnly)

  /// Follows no redirects, and throws ``HTTPClientError/redirectRefused`` when a request is
  /// answered with one.
  ///
  /// Requests that carry credentials get this policy whatever the client's policy is.
  public static let refuseAll: RedirectPolicy = RedirectPolicy(.refuseAll)

  /// Whether to follow a redirect.
  ///
  /// - Parameters:
  ///   - target: The address the redirect names.
  ///   - original: The address the request was first sent to, before any redirect.
  /// - Returns: `true` if the policy follows the redirect.
  func allows(redirectTo target: URL?, from original: URL?) -> Bool {

    switch kind {
    case .followAll:
      return true
    case .refuseAll:
      return false
    case .sameOriginHTTPSOnly:
      guard let target, let original, let targetOrigin = Origin(target), let originalOrigin = Origin(original) else {

        return false

      }

      return targetOrigin.scheme == "https" && targetOrigin == originalOrigin
    }

  }

}

/// The scheme, host and port of an address, with the port filled in for HTTP and HTTPS when
/// the address leaves it out.
struct Origin: Hashable, Sendable {

  let scheme: String

  let host: String

  let port: Int?

  /// The origin of an address, or `nil` if it has no scheme or host.
  init?(_ url: URL) {

    guard let scheme: String = url.scheme?.lowercased(), let host: String = url.host?.lowercased(), !host.isEmpty else {

      return nil

    }

    self.scheme = scheme
    self.host = host

    if let port: Int = url.port {

      self.port = port

    } else if scheme == "https" {

      self.port = 443

    } else if scheme == "http" {

      self.port = 80

    } else {

      self.port = nil

    }

  }

}
