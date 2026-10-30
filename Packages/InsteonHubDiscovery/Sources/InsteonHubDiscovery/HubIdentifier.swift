import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonHubClient
import InsteonModem
import InsteonNetworking
import InsteonProtocol

/// Confirms a ``DiscoveredHub`` and reads its identity by asking it for Get IM Info with the
/// Hub's user name and password, within a strict policy for where those credentials may go.
///
/// A discovered Hub is only a candidate: any device that answers the Hub's buffer page the way a
/// Hub does is reported, and Insteon Connect reports whatever a Hub told Insteon's servers.
/// Asking for Get IM Info confirms a candidate really is a Hub and reads its Insteon ID,
/// category, subcategory and firmware version. It needs the user name and password printed on
/// the Hub, which the Hub's interface sends unencrypted, so the credentials go only where a Hub
/// on the local network is:
///
/// - ``HubIdentifier/identify(_:provideCredentials:onResult:)``, which identifies several
///   candidates, sends them only to a candidate at a private address on the Hub's
///   ``HubIdentifier/port``, and stops at the first candidate that rejects them, since a
///   rejection means the credentials are wrong and trying the rest would send wrong credentials
///   around the network. The caller decides, per candidate, whether to send them at all, by
///   returning them or `nil` from `provideCredentials`, so a command-line tool can ask in a
///   terminal and an app can show a prompt.
/// - ``HubIdentifier/identify(_:credentials:)``, which identifies one candidate the caller has
///   chosen deliberately, at a private address, whatever its port.
///
/// The credentials are never written to a log and never put in an error.
///
/// ```swift
/// let identifier = HubIdentifier()
/// let results = try await identifier.identify(hubs) { candidate in
///   await askTheUser(about: candidate) ? credentials : nil
/// } onResult: { candidate, outcome in
///   print(candidate.endpoint.host, outcome)
/// }
/// ```
public struct HubIdentifier: Sendable {

  /// How long a candidate has to answer Get IM Info by default: 15 seconds.
  public static let defaultTimeout: Duration = .seconds(15)

  /// The Hub's user name and password, which its interface requires.
  ///
  /// The value redacts itself when printed, so it can't reach a log that way.
  public struct Credentials: Hashable, Sendable {

    /// The Hub's user name.
    public var user: String

    /// The Hub's password.
    public var password: String

    /// Creates credentials.
    ///
    /// - Parameters:
    ///   - user: The Hub's user name.
    ///   - password: The Hub's password.
    public init(user: String, password: String) {

      self.user = user
      self.password = password

    }

  }

  /// What came of asking a candidate for Get IM Info.
  ///
  /// A failure carries its underlying error, which never carries the credentials.
  public enum Outcome: Sendable {

    /// The candidate answered Get IM Info, confirming it's a Hub, and reported this identity.
    case identified(ModemInfo)

    /// The candidate's address isn't a private address, so no credentials were sent.
    case skippedNonPrivateAddress

    /// The candidate isn't on the Hub's port, so no credentials were sent. Only
    /// ``HubIdentifier/identify(_:provideCredentials:onResult:)`` reports this.
    case skippedNonHubPort

    /// The caller chose not to send credentials to the candidate.
    case declined

    /// The candidate didn't answer Get IM Info before the timeout.
    case didNotAnswer

    /// The candidate rejected the credentials with `401 Unauthorized` or `403 Forbidden`, which
    /// stops ``HubIdentifier/identify(_:provideCredentials:onResult:)`` so the wrong credentials
    /// aren't sent to any more candidates. The error carries no credentials.
    case rejected(any Error)

    /// Asking the candidate failed for another reason. The error carries no credentials.
    case failed(any Error)

    /// Whether this outcome is the candidate rejecting the credentials.
    public var isAuthenticationFailure: Bool {

      if case .rejected = self {

        return true

      }

      return false

    }

  }

  /// The client the requests are sent with, before the Hub's credentials are added to it.
  public let httpClient: any HTTPClient

  /// The Hub's port, which the many-candidate policy requires a candidate to be on.
  public let port: Int

  /// How long a candidate has to answer Get IM Info.
  public let timeout: Duration

  /// Creates an identifier.
  ///
  /// - Parameters:
  ///   - httpClient: The client to send requests with, before the Hub's credentials are added.
  ///     Defaults to a `URLSessionHTTPClient`.
  ///   - port: The Hub's port, which a candidate must be on for
  ///     ``HubIdentifier/identify(_:provideCredentials:onResult:)`` to send it credentials.
  ///     Defaults to `HubEndpoint.defaultPort`.
  ///   - timeout: How long a candidate has to answer Get IM Info. Defaults to
  ///     ``HubIdentifier/defaultTimeout``.
  public init(
    httpClient: any HTTPClient = URLSessionHTTPClient(),
    port: Int = HubEndpoint.defaultPort,
    timeout: Duration = HubIdentifier.defaultTimeout
  ) {

    self.httpClient = httpClient
    self.port = port
    self.timeout = timeout

  }

  /// Identifies several candidates, sending the Hub's credentials only to a candidate at a
  /// private address on the Hub's ``HubIdentifier/port``, and stopping at the first that rejects
  /// them.
  ///
  /// For each candidate, in order: a candidate not on the Hub's port is skipped
  /// (``HubIdentifier/Outcome/skippedNonHubPort``), then a candidate not at a private address is
  /// skipped (``HubIdentifier/Outcome/skippedNonPrivateAddress``), both without asking the caller
  /// for credentials. Otherwise `provideCredentials` is asked; returning `nil` declines the
  /// candidate (``HubIdentifier/Outcome/declined``), and returning credentials sends Get IM Info.
  /// The first candidate that rejects the credentials ends the run, so no later candidate is
  /// contacted.
  ///
  /// - Parameters:
  ///   - hubs: The candidates to identify, in order.
  ///   - provideCredentials: Asked, for each eligible candidate, for the credentials to send, or
  ///     `nil` to send none. This is where a caller takes the per-candidate decision to send the
  ///     Hub's password.
  ///   - onResult: Called with each candidate and its outcome as it's reached, for progress.
  /// - Returns: Each candidate reached and its outcome, up to and including a rejection.
  /// - Throws: `CancellationError` if the task is canceled, or an error `provideCredentials`
  ///   throws.
  @discardableResult
  public func identify(
    _ hubs: [DiscoveredHub],
    provideCredentials: @Sendable (DiscoveredHub) async throws -> Credentials?,
    onResult: @Sendable (DiscoveredHub, Outcome) -> Void = { _, _ in }
  ) async throws -> [(hub: DiscoveredHub, outcome: Outcome)] {

    var results: [(hub: DiscoveredHub, outcome: Outcome)] = []

    for hub in hubs {

      let outcome: Outcome

      // The port is checked before the address, so a candidate on another port is told the Hub's
      // port before anything about its address.
      if hub.endpoint.port != port {

        outcome = .skippedNonHubPort

      } else if !Self.isPrivate(hub.endpoint.host) {

        outcome = .skippedNonPrivateAddress

      } else if let credentials = try await provideCredentials(hub) {

        outcome = try await identify(hub, credentials: credentials)

      } else {

        outcome = .declined

      }

      onResult(hub, outcome)
      results.append((hub, outcome))

      if outcome.isAuthenticationFailure {

        break

      }

    }

    return results

  }

  /// Identifies one candidate the caller has chosen, sending the Hub's credentials to it only if
  /// it's at a private address.
  ///
  /// This sends the credentials whatever the candidate's port, so the caller takes
  /// responsibility for having chosen the candidate; it's for a Hub named deliberately, not for
  /// a candidate picked from a search. The address must still be private, where a Hub on the
  /// local network is.
  ///
  /// - Parameters:
  ///   - hub: The candidate to identify.
  ///   - credentials: The Hub's user name and password.
  /// - Returns: The outcome. Never ``HubIdentifier/Outcome/skippedNonHubPort`` or
  ///   ``HubIdentifier/Outcome/declined``.
  /// - Throws: `CancellationError` if the task is canceled.
  public func identify(_ hub: DiscoveredHub, credentials: Credentials) async throws -> Outcome {

    guard Self.isPrivate(hub.endpoint.host) else {

      return .skippedNonPrivateAddress

    }

    do {

      guard let info = try await modemInfo(at: hub.endpoint, credentials: credentials) else {

        return .didNotAnswer

      }

      return .identified(info)

    } catch is CancellationError {

      throw CancellationError()

    } catch {

      return Self.isRejection(error) ? .rejected(error) : .failed(error)

    }

  }

  /// Asks a Hub for Get IM Info, giving up after ``HubIdentifier/timeout``.
  ///
  /// The request runs in a task of its own that isn't waited for once the time is up, so a
  /// request that doesn't stop when canceled can't hold up the caller past the timeout.
  ///
  /// - Returns: The Hub's identity, or `nil` if it didn't answer in time.
  private func modemInfo(at endpoint: HubEndpoint, credentials: Credentials) async throws -> ModemInfo? {

    let connection = HubConnection(
      hub: Hub(endpoint: endpoint, user: credentials.user, password: credentials.password, httpClient: httpClient)
    )
    let result = OneShot<ModemInfo?>()

    let request = Task {

      do {

        let info: ModemInfo = try await Modem.withConnection(connection) { modem in

          try await modem.modemInfo()

        }

        result.finish(.success(info))

      } catch {

        result.finish(.failure(error))

      }

    }

    let timer = Task {

      try? await Task.sleep(for: timeout)
      result.finish(.success(nil))

    }

    defer {

      request.cancel()
      timer.cancel()

    }

    return try await withTaskCancellationHandler {

      try await result.value()

    } onCancel: {

      result.finish(.failure(CancellationError()))

    }

  }

  /// Whether a host is a private IPv4 address, where a Hub on the local network is.
  private static func isPrivate(_ host: String) -> Bool {

    IPv4Subnet(address: host, prefixLength: 32)?.isPrivate == true

  }

  /// Whether an error is the Hub rejecting the user name and password.
  private static func isRejection(_ error: any Error) -> Bool {

    switch error {
    case HubError.unexpectedStatus(401), HubError.unexpectedStatus(403):
      return true
    default:
      return false
    }

  }

}

extension HubIdentifier.Credentials: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

  /// A placeholder that shows neither the user name nor the password.
  public var description: String {

    "Credentials(redacted)"

  }

  /// A placeholder that shows neither the user name nor the password.
  public var debugDescription: String {

    description

  }

  /// A mirror with no children, so `dump(_:)` shows neither value.
  public var customMirror: Mirror {

    Mirror(self, children: [Mirror.Child]())

  }

}
