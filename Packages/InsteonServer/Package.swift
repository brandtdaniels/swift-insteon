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
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "5.0.3")),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.11.0")
  ],
  targets: [
    .target(
      name: "InsteonHTTP",
      dependencies: [
        .product(name: "InsteonService", package: "swift-insteon"),
        .product(name: "InsteonCore", package: "swift-insteon"),
        .product(name: "InsteonProtocol", package: "swift-insteon"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        .product(name: "HTTPTypes", package: "swift-http-types")
      ]
    ),
    .testTarget(
      name: "InsteonHTTPTests",
      dependencies: ["InsteonHTTP", .product(name: "InsteonService", package: "swift-insteon"), .product(name: "InsteonCore", package: "swift-insteon"), .product(name: "HummingbirdTesting", package: "hummingbird"), .product(name: "Hummingbird", package: "hummingbird"), .product(name: "HTTPTypes", package: "swift-http-types"), .product(name: "ServiceLifecycleTestKit", package: "swift-service-lifecycle")]
    ),
    .target(
      name: "InsteonServerSupport",
      dependencies: [
        "InsteonHTTP",
        .product(name: "InsteonService", package: "swift-insteon"),
        .product(name: "InsteonCore", package: "swift-insteon"),
        .product(name: "InsteonCLISupport", package: "swift-insteon"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdCore", package: "hummingbird")
      ]
    ),
    .executableTarget(name: "insteon-server", dependencies: ["InsteonServerSupport"]),
    .testTarget(
      name: "InsteonServerTests",
      dependencies: ["InsteonServerSupport"]
    )
  ]
)
