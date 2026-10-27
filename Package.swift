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
    .library(name: "InsteonProtocol", targets: ["InsteonProtocol"]),
    .library(name: "InsteonNetworking", targets: ["InsteonNetworking"]),
    .library(name: "InsteonHubClient", targets: ["InsteonHubClient"]),
    .library(name: "InsteonModem", targets: ["InsteonModem"])
  ],
  targets: [
    .target(
      name: "InsteonProtocol",
      path: "Packages/InsteonProtocol/Sources/InsteonProtocol"
    ),
    .testTarget(
      name: "InsteonProtocolTests",
      dependencies: ["InsteonProtocol"],
      path: "Packages/InsteonProtocol/Tests/InsteonProtocolTests"
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
      dependencies: ["InsteonModem", "InsteonNetworking"],
      path: "Packages/InsteonHubClient/Sources/InsteonHubClient"
    ),
    .testTarget(
      name: "InsteonHubClientTests",
      dependencies: ["InsteonHubClient", "InsteonModem", "InsteonNetworking", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonHubClient/Tests/InsteonHubClientTests"
    ),

    .target(
      name: "InsteonModem",
      dependencies: ["InsteonProtocol"],
      path: "Packages/InsteonModem/Sources/InsteonModem"
    ),
    .testTarget(
      name: "InsteonModemTests",
      dependencies: ["InsteonModem", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonModem/Tests/InsteonModemTests"
    ),

    // Test doubles shared by the test targets. Not a product.
    .target(
      name: "InsteonTestSupport",
      path: "Packages/InsteonTestSupport/Sources/InsteonTestSupport"
    )
  ]
)
