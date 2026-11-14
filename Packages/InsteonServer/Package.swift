// swift-tools-version: 6.3

import PackageDescription

// The server is optional: its framework is outside the libraries' dependency graph.
let package = Package(
  name: "InsteonServer",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "insteon-server", targets: ["insteon-server"])],
  dependencies: [
    .package(name: "swift-insteon", path: "../.."),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "2.28.1")),
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "InsteonServerSupport",
      dependencies: [
        .product(name: "InsteonGateway", package: "swift-insteon"),
        .product(name: "InsteonCore", package: "swift-insteon"),
        .product(name: "InsteonCLISupport", package: "swift-insteon"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdCore", package: "hummingbird"),
        .product(name: "HTTPTypes", package: "swift-http-types")
      ]
    ),
    .executableTarget(name: "insteon-server", dependencies: ["InsteonServerSupport", .product(name: "InsteonGateway", package: "swift-insteon")]),
    .testTarget(
      name: "InsteonServerTests",
      dependencies: [
        "InsteonServerSupport",
        .product(name: "InsteonGateway", package: "swift-insteon"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdTesting", package: "hummingbird")
      ]
    )
  ]
)
