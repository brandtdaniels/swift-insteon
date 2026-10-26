/// Obtains tokens from the Insteon OAuth2 endpoints.
///
/// This is where an OAuth library plugs in; `CachingAccessTokenProvider` decides when to call it.
public protocol TokenAuthorizer {

  func authorize(completion: @escaping (Result<AccessToken, Error>) -> Void)

  func refresh(
    _ token: AccessToken,
    completion: @escaping (Result<AccessToken, Error>) -> Void
  )

}
