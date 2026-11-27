import InsteonService

/// The calls a service offers, the same on every path that reaches it.
///
/// They are the service's own roles, so code written against `DeviceQuerying` and
/// `DeviceCommanding` runs on a path, a ``ClientConnection`` or the service itself.
///
/// A call throws ``ConnectionPathError/notReached(_:)`` only when it can prove that no byte of the
/// request left, so the connection may pass it to another path. A failure after the request may
/// have been sent is ``ConnectionPathError/interrupted``, however it happened.
public protocol ConnectionCalls: DeviceQuerying, DeviceCommanding {

  /// Releases what the calls hold, such as a connection. The connection calls it on calls it opened
  /// and then didn't use.
  func close() async

  /// Subscribes to the service's numbered events, resuming after `cursor` when it has them.
  ///
  /// The default throws ``ConnectionPathError/unsupported``, for a path that carries no events.
  /// A subscription that is lost later ends by throwing, and the connection resubscribes.
  func sequencedEvents(after cursor: EventCursor?) async throws -> SequencedEvents

  /// The scenes the service lists from the ALL-Link databases it holds. The call sends nothing to
  /// hardware. The default throws ``ConnectionPathError/unsupported``, for a path that carries no
  /// scenes.
  func scenes() async throws -> SceneList

  /// Asks the service to read the ALL-Link databases from the hardware, then answers the list. The
  /// default throws ``ConnectionPathError/unsupported``.
  func refreshScenes() async throws -> SceneList

  /// Runs a scene the modem controls. The key makes a repeat of the same run return the answer
  /// recorded for it and send nothing, so a caller that lost the answer asks again with the same key.
  /// The default throws ``ConnectionPathError/unsupported``.
  func runScene(_ number: Int, action: SceneAction, idempotencyKey: String) async throws -> SceneRunReceipt

}

extension ConnectionCalls {

  public func close() async {}

  public func sequencedEvents(after cursor: EventCursor?) async throws -> SequencedEvents {
    throw ConnectionPathError.unsupported
  }

  public func scenes() async throws -> SceneList { throw ConnectionPathError.unsupported }

  public func refreshScenes() async throws -> SceneList { throw ConnectionPathError.unsupported }

  public func runScene(_ number: Int, action: SceneAction, idempotencyKey: String) async throws -> SceneRunReceipt {
    throw ConnectionPathError.unsupported
  }

}

/// One way to reach the service: a Hub on the local network, the service at a local address, or a
/// route a transport carries.
public protocol ConnectionPath: Sendable {

  /// Names the path in an error and in ``ClientConnection/currentPath``.
  var name: String { get }

  /// Reaches the service and returns its calls.
  ///
  /// - Throws: ``ConnectionPathError/notReached(_:)`` when nothing answered, so nothing was sent, or
  ///   ``ConnectionPathError/unauthorized`` when the service refused the credential.
  func open() async throws -> any ConnectionCalls

}

/// Why a path or a call on it failed, in terms the connection acts on.
public enum ConnectionPathError: Error, Equatable, Sendable {

  /// Nothing answered, so nothing was sent. The reason is for a person to read and holds no
  /// address or credential.
  case notReached(String)

  /// The service refused the credential on this path. Each path carries its own credential, so
  /// another path may accept its own.
  case unauthorized

  /// The credential is good but its scope is too low for the call. Pairing again doesn't fix it:
  /// the service has to issue a credential with a wider scope.
  case forbidden

  /// The path answered with something this library can't read, or with something that isn't the
  /// service. A 3xx or 4xx answer that isn't the service's own refusal means the service did not
  /// accept the request, so nothing was done. An unreadable 2xx answer is different: the service
  /// accepted the request and may have acted on it. The connection drops the path, so the next call
  /// checks it again.
  case badResponse

  /// The path was lost after a request may have reached the service.
  case interrupted

  /// The path doesn't carry this kind of call. Nothing was sent, and the path stays open for the
  /// calls it does carry.
  case unsupported

}
