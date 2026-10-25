![Swift](https://github.com/brandtdaniels/swift-insteon/workflows/Swift/badge.svg)

# swift-insteon

Swift packages for working with Insteon devices, consolidated from the individual repositories into a single monorepo.

All libraries are built from the root `Package.swift` and share one dependency graph, so changes that span packages can be made and tested in a single commit.

| Library | Description | Depends on |
| --- | --- | --- |
| [AuthClient](Packages/AuthClient) | OAuth2 wrapper around OAuthSwift | OAuthSwift |
| [RequestClient](Packages/RequestClient) | Protocol and `URLSession` implementation for network requests | — |
| [InsteonMessage](Packages/InsteonMessage) | Types for forming Insteon messages | — |
| [InsteonSerialCommand](Packages/InsteonSerialCommand) | Types for forming Insteon serial commands | InsteonMessage |
| [InsteonApiClient](Packages/InsteonApiClient) | Client for the Insteon cloud API | AuthClient, RequestClient, KeychainAccess |
| [InsteonHubClient](Packages/InsteonHubClient) | Client for sending requests to an Insteon Hub | RequestClient, InsteonMessage, InsteonSerialCommand |

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

## History

Each original repository's history was imported with its files rewritten into `Packages/<Name>`, so `git log -- Packages/<Name>` shows that package's full history.
