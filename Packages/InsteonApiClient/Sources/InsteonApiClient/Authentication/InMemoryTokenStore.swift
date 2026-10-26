/// Keeps the token for the lifetime of the process.
public final class InMemoryTokenStore {

  private var token: AccessToken?

  public init(token: AccessToken? = nil) {

    self.token = token

  }

}

// MARK: - TokenStore

extension InMemoryTokenStore: TokenStore {

  public func load() -> AccessToken? {

    return token

  }

  public func save(_ token: AccessToken) {

    self.token = token

  }

  public func clear() {

    token = nil

  }

}
