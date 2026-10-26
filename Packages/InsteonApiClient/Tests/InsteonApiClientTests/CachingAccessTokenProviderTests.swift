import XCTest
@testable import InsteonApiClient

final class CachingAccessTokenProviderTests: XCTestCase {

  let now = Date(timeIntervalSince1970: 1_000_000)

  var authorizer: MockTokenAuthorizer!

  var store: InMemoryTokenStore!

  var tokenProvider: CachingAccessTokenProvider!

  override func setUp() {

    super.setUp()

    authorizer = MockTokenAuthorizer()
    store = InMemoryTokenStore()

    let now = self.now
    tokenProvider = CachingAccessTokenProvider(authorizer: authorizer, store: store, now: { now })

  }

  func testAuthorizesAndStoresTokenWhenNoneIsStored() {

    let authorizedToken = token("authorized", expiresIn: 3600)
    authorizer.authorizeResult = .success(authorizedToken)

    XCTAssertEqual(requestToken(), authorizedToken)
    XCTAssertEqual(store.load(), authorizedToken)
    XCTAssertEqual(authorizer.authorizeCallCount, 1)

  }

  func testReturnsStoredTokenWhileValid() {

    let storedToken = token("stored", expiresIn: 3600)
    store.save(storedToken)

    XCTAssertEqual(requestToken(), storedToken)
    XCTAssertEqual(authorizer.authorizeCallCount, 0)
    XCTAssertTrue(authorizer.refreshedTokens.isEmpty)

  }

  func testRefreshesExpiredToken() {

    let expiredToken = token("expired", refreshToken: "refresh", expiresIn: -1)
    let refreshedToken = token("refreshed", expiresIn: 3600)
    store.save(expiredToken)
    authorizer.refreshResult = .success(refreshedToken)

    XCTAssertEqual(requestToken(), refreshedToken)
    XCTAssertEqual(authorizer.refreshedTokens, [expiredToken])
    XCTAssertEqual(store.load(), refreshedToken)

  }

  func testAuthorizesWhenRefreshFails() {

    let authorizedToken = token("authorized", expiresIn: 3600)
    store.save(token("expired", refreshToken: "refresh", expiresIn: -1))
    authorizer.refreshResult = .failure(TestError.failed)
    authorizer.authorizeResult = .success(authorizedToken)

    XCTAssertEqual(requestToken(), authorizedToken)
    XCTAssertEqual(store.load(), authorizedToken)

  }

  func testAuthorizesWhenExpiredTokenCannotBeRefreshed() {

    let authorizedToken = token("authorized", expiresIn: 3600)
    store.save(token("expired", expiresIn: -1))
    authorizer.authorizeResult = .success(authorizedToken)

    XCTAssertEqual(requestToken(), authorizedToken)
    XCTAssertTrue(authorizer.refreshedTokens.isEmpty)

  }

  func testInvalidateClearsStoredToken() {

    store.save(token("stored", expiresIn: 3600))

    tokenProvider.invalidateAccessToken()

    XCTAssertNil(store.load())

  }

  func testExpiresInIsMeasuredInSeconds() {

    let accessToken = AccessToken(value: "token", expiresIn: 60, issuedAt: now)

    XCTAssertFalse(accessToken.isExpired(at: now.addingTimeInterval(59)))
    XCTAssertTrue(accessToken.isExpired(at: now.addingTimeInterval(60)))

  }

  private func token(_ value: String, refreshToken: String? = nil, expiresIn: TimeInterval) -> AccessToken {

    return AccessToken(value: value, refreshToken: refreshToken, expiresIn: expiresIn, issuedAt: now)

  }

  private func requestToken() -> AccessToken? {

    var receivedToken: AccessToken?

    tokenProvider.accessToken { result in

      receivedToken = try? result.get()

    }

    return receivedToken

  }

  static var allTests = [
    ("testAuthorizesAndStoresTokenWhenNoneIsStored", testAuthorizesAndStoresTokenWhenNoneIsStored),
    ("testReturnsStoredTokenWhileValid", testReturnsStoredTokenWhileValid),
    ("testRefreshesExpiredToken", testRefreshesExpiredToken),
    ("testAuthorizesWhenRefreshFails", testAuthorizesWhenRefreshFails),
    ("testAuthorizesWhenExpiredTokenCannotBeRefreshed", testAuthorizesWhenExpiredTokenCannotBeRefreshed),
    ("testInvalidateClearsStoredToken", testInvalidateClearsStoredToken),
    ("testExpiresInIsMeasuredInSeconds", testExpiresInIsMeasuredInSeconds)
  ]

}
