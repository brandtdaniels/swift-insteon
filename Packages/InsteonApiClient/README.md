# InsteonApiClient

A client for the Insteon cloud API (v2).

`ApiClient` depends only on abstractions, so each concern can be swapped independently:

| Concern | Protocol | Provided implementations |
| --- | --- | --- |
| Transport | `HTTPClient` (InsteonNetworking) | `URLSessionHTTPClient` |
| Authentication headers and retry | `HTTPClient` decorator | `AuthenticatingHTTPClient` |
| Obtaining tokens (OAuth) | `TokenAuthorizer` | Bring your own, see below |
| Deciding when to authorize or refresh | `AccessTokenProvider` | `CachingAccessTokenProvider` |
| Persisting tokens | `TokenStore` | `InMemoryTokenStore`, `KeychainTokenStore` (in the `InsteonApiClientKeychain` product) |
| Decoding responses | `ResponseDecoder` | `InsteonResponseDecoder` |

## Example

```swift
import InsteonApiClient
import InsteonApiClientKeychain

let tokenProvider = CachingAccessTokenProvider(
  authorizer: MyOAuthAuthorizer(),
  store: KeychainTokenStore()
)

let apiClient = ApiClient(apiKey: "your-client-id", tokenProvider: tokenProvider)

apiClient.request(GetHouses()) { result in

  // Do something with result

}
```

Load the client ID from configuration at runtime; don't commit it.

## Using AuthClient for OAuth

[AuthClient](https://github.com/brandtdaniels/AuthClient) wraps OAuthSwift. Adapt it to `TokenAuthorizer`:

```swift
import AuthClient
import InsteonApiClient

struct AuthClientTokenAuthorizer: TokenAuthorizer {

  let authClient: AuthClientProtocol

  func authorize(completion: @escaping (Result<AccessToken, Error>) -> Void) {

    authClient.authorize { result in

      completion(result.map(AccessToken.init).mapError { $0 as Error })

    }

  }

  func refresh(_ token: AccessToken, completion: @escaping (Result<AccessToken, Error>) -> Void) {

    guard let refreshToken = token.refreshToken else {

      return authorize(completion: completion)

    }

    authClient.renewAccessToken(withRefreshToken: refreshToken) { result in

      completion(result.map(AccessToken.init).mapError { $0 as Error })

    }

  }

}

extension AccessToken {

  init(_ response: TokenResponse) {

    self.init(
      value: response.accessToken,
      refreshToken: response.refreshToken,
      expiresIn: response.expiresIn
    )

  }

}
```
