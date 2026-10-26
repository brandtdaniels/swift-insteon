/// Persists the current access token between requests and launches.
public protocol TokenStore {

  func load() -> AccessToken?

  func save(_ token: AccessToken)

  func clear()

}
