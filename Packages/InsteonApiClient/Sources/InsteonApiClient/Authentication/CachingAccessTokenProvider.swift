import Foundation

/// Serves the stored token while it is valid, refreshes it once it expires,
/// and falls back to a full authorization when there is no token or the refresh fails.
public final class CachingAccessTokenProvider {

  private let authorizer: TokenAuthorizer

  private let store: TokenStore

  private let now: () -> Date

  public init(
    authorizer: TokenAuthorizer,
    store: TokenStore = InMemoryTokenStore(),
    now: @escaping () -> Date = { Date() }
  ) {

    self.authorizer = authorizer
    self.store = store
    self.now = now

  }

}

// MARK: - AccessTokenProvider

extension CachingAccessTokenProvider: AccessTokenProvider {

  public func accessToken(completion: @escaping (Result<AccessToken, Error>) -> Void) {

    guard let token = store.load() else {

      authorize(completion: completion)

      return

    }

    guard token.isExpired(at: now()) else {

      completion(.success(token))

      return

    }

    guard token.refreshToken != nil else {

      authorize(completion: completion)

      return

    }

    authorizer.refresh(token) { result in

      switch result {

      case let .success(refreshedToken):

        self.store.save(refreshedToken)

        completion(.success(refreshedToken))

      case .failure:

        self.store.clear()

        self.authorize(completion: completion)

      }

    }

  }

  public func invalidateAccessToken() {

    store.clear()

  }

  private func authorize(completion: @escaping (Result<AccessToken, Error>) -> Void) {

    authorizer.authorize { [store] result in

      if case let .success(token) = result {

        store.save(token)

      }

      completion(result)

    }

  }

}
