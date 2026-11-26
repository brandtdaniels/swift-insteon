import InsteonService

/// The calls a home offers, the same on every path that reaches it.
///
/// They are the service's own roles, so code written against `DeviceQuerying` and
/// `DeviceCommanding` runs on a path, a ``HomeConnection`` or the service itself.
///
/// A call throws ``HomePathError/notReached(_:)`` only when it can prove that no byte of the
/// request left, so the connection may pass it to another path. A failure after the request may
/// have been sent is ``HomePathError/interrupted``, however it happened.
public protocol HomeCalls: DeviceQuerying, DeviceCommanding {

  /// Releases what the calls hold, such as a connection. The connection calls it on calls it opened
  /// and then didn't use.
  func close() async

}

extension HomeCalls {

  public func close() async {}

}

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

  /// The home answered with something this library can't read, or something that isn't the service. The connection drops the path, so the next call checks it again.
  case badResponse

  /// The path was lost after a request may have reached the home.
  case interrupted

}
