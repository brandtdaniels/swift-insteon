// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "swift-insteon",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
    .tvOS(.v16),
    .watchOS(.v9),
    .visionOS(.v1)
  ],
  products: [
    .library(name: "InsteonMessage", targets: ["InsteonMessage"]),
    .library(name: "InsteonSerialCommand", targets: ["InsteonSerialCommand"]),
    .library(name: "InsteonNetworking", targets: ["InsteonNetworking"]),
    .library(name: "InsteonHubClient", targets: ["InsteonHubClient"])
  ],
  targets: [
    .target(
      name: "InsteonMessage",
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
      name: "InsteonNetworking",
      path: "Packages/InsteonNetworking/Sources/InsteonNetworking"
    ),
    .testTarget(
      name: "InsteonNetworkingTests",
      dependencies: ["InsteonNetworking"],
      path: "Packages/InsteonNetworking/Tests/InsteonNetworkingTests"
    ),

    .target(
      name: "InsteonHubClient",
      dependencies: ["InsteonNetworking", "InsteonSerialCommand"],
      path: "Packages/InsteonHubClient/Sources/InsteonHubClient"
    ),
    .testTarget(
      name: "InsteonHubClientTests",
      dependencies: ["InsteonHubClient", "InsteonNetworking", "InsteonSerialCommand", "InsteonMessage"],
      path: "Packages/InsteonHubClient/Tests/InsteonHubClientTests"
    )
  ]
)
