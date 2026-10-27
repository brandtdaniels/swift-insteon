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
    .library(name: "InsteonNetworking", targets: ["InsteonNetworking"])
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
    )
  ]
)
