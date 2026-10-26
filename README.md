![Swift](https://github.com/brandtdaniels/swift-insteon/workflows/Swift/badge.svg)

# swift-insteon

Swift packages for working with Insteon devices, consolidated from the individual repositories into a single monorepo.

All libraries are built from the root `Package.swift` and share one dependency graph, so changes that span packages can be made and tested in a single commit.

| Library | Description | Depends on |
| --- | --- | --- |
| [InsteonNetworking](Packages/InsteonNetworking) | The `HTTPClient` abstraction every client talks through, with a `URLSession` adapter | — |
| [InsteonMessage](Packages/InsteonMessage) | Types for forming Insteon messages | — |
| [InsteonSerialCommand](Packages/InsteonSerialCommand) | Types for forming Insteon serial commands | InsteonMessage |
| [InsteonHubClient](Packages/InsteonHubClient) | Client for sending requests to an Insteon Hub | InsteonNetworking, InsteonMessage, InsteonSerialCommand |
| [InsteonApiClient](Packages/InsteonApiClient) | Client for the Insteon cloud API | InsteonNetworking |
| InsteonApiClientKeychain | Keychain-backed token storage for InsteonApiClient | InsteonApiClient, KeychainAccess |

## Design

The clients depend on small protocols rather than concrete networking or OAuth libraries, so consumers choose the implementation:

* **Transport**: `HubClient` and `ApiClient` only know `HTTPClient`. `URLSessionHTTPClient` is the default adapter; conform anything else (Alamofire, a mock) to use it instead.
* **Cross-cutting behavior is layered with decorators**: `BasicAuthenticationHTTPClient` adds hub credentials and `AuthenticatingHTTPClient` adds API keys and bearer tokens, each wrapping any `HTTPClient`.
* **OAuth is a strategy**: `ApiClient` needs only an `AccessTokenProvider`. `CachingAccessTokenProvider` decides when to authorize or refresh through a `TokenAuthorizer` you supply, and persists tokens through a `TokenStore`.
* **Optional dependencies stay optional**: KeychainAccess is only pulled in by the `InsteonApiClientKeychain` product.

## Usage

Add the package once and pick the products you need:

```swift
.package(url: "https://github.com/brandtdaniels/swift-insteon", .branch("main"))
```

```swift
.target(
  name: "MyApp",
  dependencies: [
    .product(name: "InsteonHubClient", package: "swift-insteon")
  ]
)
```

## Development

```sh
swift build
swift test
```

## Migrating from the individual packages

* `RequestClient` and `AuthClient` are no longer dependencies. They live on in their own repositories; adapt them to `HTTPClient` and `TokenAuthorizer` (see [InsteonApiClient](Packages/InsteonApiClient)) if you want to keep using them.
* `HubClient(credentials:address:requestClient:)` is now `HubClient(credentials:address:httpClient:)`, and `send` delivers `Result<Data, Error>`. Non-2xx responses fail with `HubClientError.response(statusCode:)`.
* `ApiClient(_:_:_:)` is now `ApiClient(apiKey:tokenProvider:httpClient:)`, and results are no longer optional. Requests now carry the `Authentication` and `Authorization` headers the API requires.
* The `Keychain` protocol and `InsteonKeychain` are replaced by `TokenStore` and `KeychainTokenStore`.

## History

Each original repository's history was imported with its files rewritten into `Packages/<Name>`, so `git log -- Packages/<Name>` shows that package's full history.
