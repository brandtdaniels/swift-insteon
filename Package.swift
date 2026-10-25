// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-insteon",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15)
  ],
  products: [
    // Products define the executables and libraries produced by a package, and make them visible to other packages.
    .library(name: "AuthClient", targets: ["AuthClient"]),
    .library(name: "RequestClient", targets: ["RequestClient"]),
    .library(name: "InsteonMessage", targets: ["InsteonMessage"]),
    .library(name: "InsteonSerialCommand", targets: ["InsteonSerialCommand"]),
    .library(name: "InsteonApiClient", targets: ["InsteonApiClient"]),
    .library(name: "InsteonHubClient", targets: ["InsteonHubClient"])
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(
      url: "https://github.com/OAuthSwift/OAuthSwift",
      .upToNextMajor(from: "2.1.2")
    ),
    .package(
      url: "https://github.com/kishikawakatsumi/KeychainAccess",
      .upToNextMajor(from: "4.2.0")
    )
  ],
  targets: [
    // Each library lives in Packages/<Name> with its own Sources and Tests directories.
    .target(
      name: "AuthClient",
      dependencies: ["OAuthSwift"],
      path: "Packages/AuthClient/Sources/AuthClient"
    ),
    .testTarget(
      name: "AuthClientTests",
      dependencies: ["AuthClient"],
      path: "Packages/AuthClient/Tests/AuthClientTests"
    ),

    .target(
      name: "RequestClient",
      dependencies: [],
      path: "Packages/RequestClient/Sources/RequestClient"
    ),

    .target(
      name: "InsteonMessage",
      dependencies: [],
      path: "Packages/InsteonMessage/Sources/InsteonMessage"
    ),
    .testTarget(
      name: "InsteonMessageTests",
      dependencies: ["InsteonMessage"],
      path: "Packages/InsteonMessage/Tests/InsteonMessageTests"
    ),

    .target(
      name: "InsteonSerialCommand",
      dependencies: ["InsteonMessage"],
      path: "Packages/InsteonSerialCommand/Sources/InsteonSerialCommand"
    ),
    .testTarget(
      name: "InsteonSerialCommandTests",
      dependencies: ["InsteonSerialCommand", "InsteonMessage"],
      path: "Packages/InsteonSerialCommand/Tests/InsteonSerialCommandTests"
    ),

    .target(
      name: "InsteonApiClient",
      dependencies: ["AuthClient", "KeychainAccess", "RequestClient"],
      path: "Packages/InsteonApiClient/Sources/InsteonApiClient"
    ),
    .testTarget(
      name: "InsteonApiClientTests",
      dependencies: ["InsteonApiClient", "AuthClient", "RequestClient"],
      path: "Packages/InsteonApiClient/Tests/InsteonApiClientTests"
    ),

    .target(
      name: "InsteonHubClient",
      dependencies: ["RequestClient", "InsteonMessage", "InsteonSerialCommand"],
      path: "Packages/InsteonHubClient/Sources/InsteonHubClient"
    ),
    .testTarget(
      name: "InsteonHubClientTests",
      dependencies: ["InsteonHubClient", "RequestClient", "InsteonMessage", "InsteonSerialCommand"],
      path: "Packages/InsteonHubClient/Tests/InsteonHubClientTests"
    )
  ]
)
