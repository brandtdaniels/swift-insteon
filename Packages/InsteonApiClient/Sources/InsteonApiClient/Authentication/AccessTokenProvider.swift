/// Supplies the access token `AuthenticatingHTTPClient` attaches to each request.
public protocol AccessTokenProvider {

  func accessToken(completion: @escaping (Result<AccessToken, Error>) -> Void)

  /// Discards the current token, for example after the API has rejected it.
  func invalidateAccessToken()

}
