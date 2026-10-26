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
    .library(name: "InsteonNetworking", targets: ["InsteonNetworking"]),
    .library(name: "InsteonMessage", targets: ["InsteonMessage"]),
    .library(name: "InsteonSerialCommand", targets: ["InsteonSerialCommand"]),
    .library(name: "InsteonHubClient", targets: ["InsteonHubClient"]),
    .library(name: "InsteonApiClient", targets: ["InsteonApiClient"]),
    .library(name: "InsteonApiClientKeychain", targets: ["InsteonApiClientKeychain"])
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(
      url: "https://github.com/kishikawakatsumi/KeychainAccess",
      .upToNextMajor(from: "4.2.0")
    )
  ],
  targets: [
    // Each library lives in Packages/<Name> with its own Sources and Tests directories.
    .target(
      name: "InsteonNetworking",
      dependencies: [],
      path: "Packages/InsteonNetworking/Sources/InsteonNetworking"
    ),
    .testTarget(
      name: "InsteonNetworkingTests",
      dependencies: ["InsteonNetworking"],
      path: "Packages/InsteonNetworking/Tests/InsteonNetworkingTests"
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
      name: "InsteonHubClient",
      dependencies: ["InsteonNetworking", "InsteonMessage", "InsteonSerialCommand"],
      path: "Packages/InsteonHubClient/Sources/InsteonHubClient"
    ),
    .testTarget(
      name: "InsteonHubClientTests",
      dependencies: ["InsteonHubClient", "InsteonNetworking", "InsteonMessage", "InsteonSerialCommand"],
      path: "Packages/InsteonHubClient/Tests/InsteonHubClientTests"
    ),

    .target(
      name: "InsteonApiClient",
      dependencies: ["InsteonNetworking"],
      path: "Packages/InsteonApiClient/Sources/InsteonApiClient"
    ),
    .target(
      name: "InsteonApiClientKeychain",
      dependencies: ["InsteonApiClient", "KeychainAccess"],
      path: "Packages/InsteonApiClient/Sources/InsteonApiClientKeychain"
    ),
    .testTarget(
      name: "InsteonApiClientTests",
      dependencies: ["InsteonApiClient", "InsteonNetworking"],
      path: "Packages/InsteonApiClient/Tests/InsteonApiClientTests"
    )
  ]
)
