import Foundation

/// Keeps small secrets, such as a client token, where the host keeps them safely.
///
/// A host gives its own: the Keychain on Apple platforms, a file readable only by its owner, or
/// a secret service elsewhere. The library never writes a secret anywhere else.
public protocol SecretStore: Sendable {

  /// Stores a secret under an account, replacing any there.
  func save(_ secret: String, account: String) async throws

  /// The secret under an account, or `nil` when there is none.
  func load(account: String) async throws -> String?

  /// Removes the secret under an account. Removing one that isn't there is not an error.
  func remove(account: String) async throws

}

/// A ``SecretStore`` that holds secrets in memory, for tests and for a host that keeps none.
public actor InMemorySecretStore: SecretStore {

  private var secrets: [String: String] = [:]

  /// Creates an empty store.
  public init() {}

  public func save(_ secret: String, account: String) { secrets[account] = secret }

  public func load(account: String) -> String? { secrets[account] }

  public func remove(account: String) { secrets[account] = nil }

  /// The accounts that hold a secret, sorted.
  public func accounts() -> [String] { secrets.keys.sorted() }

}
