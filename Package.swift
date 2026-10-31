// swift-tools-version: 6.3

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
    .library(name: "InsteonDeviceCatalog", targets: ["InsteonDeviceCatalog"]),
    .library(name: "InsteonNotifications", targets: ["InsteonNotifications"]),
    .library(name: "InsteonCore", targets: ["InsteonCore"]),
    .executable(name: "insteon", targets: ["insteon"])
  ],
  dependencies: [
    // SHA-256 for DeviceCatalogUpdater: CryptoKit on Apple platforms, BoringSSL elsewhere.
    .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "5.0.3"))
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
      dependencies: ["InsteonHubClient", "InsteonModem", "InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubDiscovery/Sources/InsteonHubDiscovery"
    ),
    .testTarget(
      name: "InsteonHubDiscoveryTests",
      dependencies: ["InsteonHubDiscovery", "InsteonHubClient", "InsteonModem", "InsteonNetworking", "InsteonProtocol"],
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
      dependencies: ["InsteonLinking", "InsteonLinkingTestSupport", "InsteonModem", "InsteonProtocol", "InsteonTestSupport"],
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
      name: "InsteonDeviceCatalog",
      dependencies: [
        "InsteonNetworking",
        "InsteonProtocol",
        .product(name: "Crypto", package: "swift-crypto")
      ],
      path: "Packages/InsteonDeviceCatalog/Sources/InsteonDeviceCatalog",
      resources: [.copy("Resources/catalog.json"), .copy("Resources/manifest.json")]
    ),
    .testTarget(
      name: "InsteonDeviceCatalogTests",
      dependencies: [
        "InsteonDeviceCatalog",
        "InsteonNetworking",
        "InsteonProtocol",
        .product(name: "Crypto", package: "swift-crypto")
      ],
      path: "Packages/InsteonDeviceCatalog/Tests/InsteonDeviceCatalogTests"
    ),

    .target(
      name: "InsteonNotifications",
      dependencies: ["InsteonDeviceCatalog", "InsteonProtocol"],
      path: "Packages/InsteonNotifications/Sources/InsteonNotifications"
    ),
    .testTarget(
      name: "InsteonNotificationsTests",
      dependencies: ["InsteonNotifications", "InsteonDeviceCatalog", "InsteonProtocol"],
      path: "Packages/InsteonNotifications/Tests/InsteonNotificationsTests"
    ),

    // The library a front end, such as an app or the `insteon` command, depends on.
    .target(
      name: "InsteonCore",
      dependencies: [
        "InsteonDeviceCatalog",
        "InsteonHubClient",
        "InsteonHubDiscovery",
        "InsteonLinking",
        "InsteonModem",
        "InsteonNetworking",
        "InsteonProtocol"
      ],
      path: "Packages/InsteonCore/Sources/InsteonCore"
    ),
    .testTarget(
      name: "InsteonCoreTests",
      dependencies: [
        "InsteonCore",
        "InsteonDeviceCatalog",
        "InsteonHubClient",
        "InsteonHubDiscovery",
        "InsteonLinking",
        "InsteonLinkingTestSupport",
        "InsteonModem",
        "InsteonProtocol",
        "InsteonTestSupport"
      ],
      path: "Packages/InsteonCore/Tests/InsteonCoreTests"
    ),

    // The `insteon` command. Its command-line parsing is in InsteonCLISupport, so it can be tested.
    // Both depend only on InsteonCore, the library every front end uses; CI builds with
    // --explicit-target-dependency-import-check error, so an import of a lower-level module fails.
    .executableTarget(
      name: "insteon",
      dependencies: ["InsteonCLISupport", "InsteonCore"],
      path: "Packages/InsteonCLI/Sources/insteon"
    ),
    .target(
      name: "InsteonCLISupport",
      dependencies: ["InsteonCore"],
      path: "Packages/InsteonCLI/Sources/InsteonCLISupport"
    ),
    .testTarget(
      name: "InsteonCLISupportTests",
      dependencies: ["InsteonCLISupport", "InsteonCore", "InsteonDeviceCatalog", "InsteonLinking", "InsteonProtocol"],
      path: "Packages/InsteonCLI/Tests/InsteonCLISupportTests"
    ),

    // Test doubles shared by the test targets. Not products. InsteonTestSupport has the clock,
    // the scripted modem connection and the HTTP stub; InsteonLinkingTestSupport has the
    // in-memory modem, which is a LinkingModem, so the tests of the layers below InsteonLinking
    // don't link it.
    .target(
      name: "InsteonTestSupport",
      dependencies: ["InsteonModem", "InsteonNetworking"],
      path: "Packages/InsteonTestSupport/Sources/InsteonTestSupport"
    ),
    .target(
      name: "InsteonLinkingTestSupport",
      dependencies: ["InsteonLinking", "InsteonModem", "InsteonProtocol"],
      path: "Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport"
    )
  ]
)
