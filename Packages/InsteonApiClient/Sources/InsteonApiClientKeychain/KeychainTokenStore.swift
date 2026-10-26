import Foundation
import InsteonApiClient
import KeychainAccess

/// Persists the access token in the keychain so it survives app launches.
public struct KeychainTokenStore {

  private let keychain: Keychain

  private let key: String

  public init(
    service: String = "com.brandtdaniels.insteon",
    key: String = "accessToken"
  ) {

    keychain = Keychain(service: service)
    self.key = key

  }

}

// MARK: - TokenStore

extension KeychainTokenStore: TokenStore {

  public func load() -> AccessToken? {

    guard let data = try? keychain.getData(key) else {

      return nil

    }

    return try? JSONDecoder().decode(AccessToken.self, from: data)

  }

  public func save(_ token: AccessToken) {

    guard let data = try? JSONEncoder().encode(token) else {

      return

    }

    try? keychain.set(data, key: key)

  }

  public func clear() {

    try? keychain.remove(key)

  }

}
