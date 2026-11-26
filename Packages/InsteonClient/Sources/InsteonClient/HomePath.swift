import InsteonService

/// The calls a home offers, the same on every path that reaches it.
///
/// They are the service's own roles, so code written against `DeviceQuerying` and
/// `DeviceCommanding` runs on a path, a ``HomeConnection`` or the service itself.
public protocol HomeCalls: DeviceQuerying, DeviceCommanding {}

/// One way to reach a home: a Hub on the local network, the service at a local address, or a
/// route a transport carries.
public protocol HomePath: Sendable {

  /// Names the path in an error and in ``HomeConnection/currentPath``.
  var name: String { get }

  /// Reaches the home and returns its calls.
  ///
  /// - Throws: ``HomePathError/notReached(_:)`` when nothing answered, so nothing was sent, or
  ///   ``HomePathError/unauthorized`` when the home refused the credential.
  func open() async throws -> any HomeCalls

}

/// Why a path or a call on it failed, in terms the connection acts on.
public enum HomePathError: Error, Equatable, Sendable {

  /// Nothing answered, so nothing was sent. The reason is for a person to read and holds no
  /// address or credential.
  case notReached(String)

  /// The home refused the credential, which another route to it would refuse too.
  case unauthorized

  /// The credential is good but its scope is too low for the call. Pairing again doesn't fix it:
  /// the home has to issue a credential with a wider scope.
  case forbidden

  /// The home answered with something this library can't read. The path is still good.
  case badResponse

  /// The path was lost after a request may have reached the home.
  case interrupted

}
