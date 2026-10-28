// swift-tools-version: 6.4

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
    .library(name: "InsteonHubDiscovery", targets: ["InsteonHubDiscovery"]),
    .library(name: "InsteonHubPro", targets: ["InsteonHubPro"]),
    .library(name: "InsteonModem", targets: ["InsteonModem"]),
    .library(name: "InsteonLinking", targets: ["InsteonLinking"]),
    .library(name: "InsteonScheduling", targets: ["InsteonScheduling"]),
    .library(name: "InsteonDeviceDatabase", targets: ["InsteonDeviceDatabase"])
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
      dependencies: ["InsteonNetworking", "InsteonTestSupport"],
      path: "Packages/InsteonNetworking/Tests/InsteonNetworkingTests"
    ),

    .target(
      name: "InsteonHubClient",
      dependencies: ["InsteonModem", "InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubClient/Sources/InsteonHubClient"
    ),
    .testTarget(
      name: "InsteonHubClientTests",
      dependencies: ["InsteonHubClient", "InsteonModem", "InsteonNetworking", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonHubClient/Tests/InsteonHubClientTests"
    ),

    .target(
      name: "InsteonHubDiscovery",
      dependencies: ["InsteonHubClient", "InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubDiscovery/Sources/InsteonHubDiscovery"
    ),
    .testTarget(
      name: "InsteonHubDiscoveryTests",
      dependencies: ["InsteonHubDiscovery", "InsteonHubClient", "InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubDiscovery/Tests/InsteonHubDiscoveryTests"
    ),

    .target(
      name: "InsteonHubPro",
      dependencies: ["InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubPro/Sources/InsteonHubPro"
    ),
    .testTarget(
      name: "InsteonHubProTests",
      dependencies: ["InsteonHubPro", "InsteonNetworking", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonHubPro/Tests/InsteonHubProTests"
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

    .target(
      name: "InsteonLinking",
      dependencies: ["InsteonModem", "InsteonProtocol"],
      path: "Packages/InsteonLinking/Sources/InsteonLinking"
    ),
    .testTarget(
      name: "InsteonLinkingTests",
      dependencies: ["InsteonLinking", "InsteonModem", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonLinking/Tests/InsteonLinkingTests"
    ),

    .target(
      name: "InsteonScheduling",
      path: "Packages/InsteonScheduling/Sources/InsteonScheduling"
    ),
    .testTarget(
      name: "InsteonSchedulingTests",
      dependencies: ["InsteonScheduling"],
      path: "Packages/InsteonScheduling/Tests/InsteonSchedulingTests"
    ),

    .target(
      name: "InsteonDeviceDatabase",
      dependencies: [
        // Only DeviceDatabaseUpdater uses it, and it needs CryptoKit.
        .target(name: "InsteonNetworking", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS])),
        "InsteonProtocol"
      ],
      path: "Packages/InsteonDeviceDatabase/Sources/InsteonDeviceDatabase",
      resources: [.copy("Resources/database.json")]
    ),
    .testTarget(
      name: "InsteonDeviceDatabaseTests",
      dependencies: [
        "InsteonDeviceDatabase",
        .target(name: "InsteonNetworking", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS])),
        "InsteonProtocol"
      ],
      path: "Packages/InsteonDeviceDatabase/Tests/InsteonDeviceDatabaseTests"
    ),

    // Test doubles shared by the test targets. Not a product.
    .target(
      name: "InsteonTestSupport",
      dependencies: ["InsteonNetworking"],
      path: "Packages/InsteonTestSupport/Sources/InsteonTestSupport"
    )
  ]
)
