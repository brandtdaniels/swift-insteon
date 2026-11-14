import Crypto
import Foundation

/// The HTTP authentication role, independent of device operations and routing.
public protocol HTTPAuthenticating: Sendable {
  /// Decides whether the supplied Authorization header is accepted.
  func authorizes(_ header: String?) -> Bool
  /// The WWW-Authenticate challenge to send when authentication fails.
  var challenge: String { get }
}

/// HTTP Basic authentication with a server password separate from the Hub's credentials.
public struct HTTPAuthentication: HTTPAuthenticating {
  private let expected: [UInt8]

  /// Validates a password without constructing a device service. Use 32 through 1024 random bytes.
  public init(password: String) throws {
    guard (32...1024).contains(password.utf8.count), !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw HTTPAuthenticationError.weakPassword }
    let credential = Data(("insteon:" + password).utf8).base64EncodedString()
    expected = SecureDigest.of(credential)
  }

  /// Accepts the fixed user name insteon and configured password, without retaining its plaintext.
  public func authorizes(_ header: String?) -> Bool {
    guard let header, header.utf8.count <= 4096 else { return false }
    // RFC 9110, "HTTP Semantics", section 11.1: auth-scheme is case-insensitive,
    // followed by one or more spaces. Only the credential is compared as secret data.
    let parts = header.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count == 2, parts[0].lowercased() == "basic" else { return false }
    return SecureDigest.matches(SecureDigest.of(String(parts[1])), expected)
  }

  /// The browser's authentication challenge.
  public var challenge: String { "Basic realm=\"Insteon service\", charset=\"UTF-8\"" }
}

/// Invalid HTTP authentication configuration.
public enum HTTPAuthenticationError: Error {
  /// The password is too short, too long or contains control characters.
  case weakPassword
}

enum SecureDigest {
  static func of(_ value: String) -> [UInt8] { Array(SHA256.hash(data: Data(value.utf8))) }
  static func matches(_ left: [UInt8], _ right: [UInt8]) -> Bool {
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices { difference |= left[index] ^ right[index] }
    return difference == 0
  }
}
