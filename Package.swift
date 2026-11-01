// swift-tools-version: 6.3

import PackageDescription

// Every target but the `insteon` command's two reads a member of a type, such as a method or an
// enum case, only from a module the file imports itself (SE-0444). The command's targets depend
// only on InsteonCore, which names lower-level types through typealiases, so they keep the
// default: their files read those types' members without importing the modules that declare
// them.
let memberImportVisibility: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]

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
      path: "Packages/InsteonProtocol/Sources/InsteonProtocol",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonProtocolTests",
      dependencies: ["InsteonProtocol"],
      path: "Packages/InsteonProtocol/Tests/InsteonProtocolTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonNetworking",
      path: "Packages/InsteonNetworking/Sources/InsteonNetworking",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonNetworkingTests",
      dependencies: ["InsteonNetworking", "InsteonTestSupport"],
      path: "Packages/InsteonNetworking/Tests/InsteonNetworkingTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonHubClient",
      dependencies: ["InsteonModem", "InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubClient/Sources/InsteonHubClient",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonHubClientTests",
      dependencies: ["InsteonHubClient", "InsteonModem", "InsteonNetworking", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonHubClient/Tests/InsteonHubClientTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonHubDiscovery",
      dependencies: ["InsteonHubClient", "InsteonModem", "InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubDiscovery/Sources/InsteonHubDiscovery",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonHubDiscoveryTests",
      dependencies: ["InsteonHubDiscovery", "InsteonHubClient", "InsteonModem", "InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubDiscovery/Tests/InsteonHubDiscoveryTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonHubPro",
      dependencies: ["InsteonNetworking", "InsteonProtocol"],
      path: "Packages/InsteonHubPro/Sources/InsteonHubPro",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonHubProTests",
      dependencies: ["InsteonHubPro", "InsteonNetworking", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonHubPro/Tests/InsteonHubProTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonModem",
      dependencies: ["InsteonProtocol"],
      path: "Packages/InsteonModem/Sources/InsteonModem",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonModemTests",
      dependencies: ["InsteonModem", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonModem/Tests/InsteonModemTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonLinking",
      dependencies: ["InsteonModem", "InsteonProtocol"],
      path: "Packages/InsteonLinking/Sources/InsteonLinking",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonLinkingTests",
      dependencies: ["InsteonLinking", "InsteonLinkingTestSupport", "InsteonModem", "InsteonProtocol", "InsteonTestSupport"],
      path: "Packages/InsteonLinking/Tests/InsteonLinkingTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonScheduling",
      path: "Packages/InsteonScheduling/Sources/InsteonScheduling",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonSchedulingTests",
      dependencies: ["InsteonScheduling"],
      path: "Packages/InsteonScheduling/Tests/InsteonSchedulingTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonDeviceCatalog",
      dependencies: [
        "InsteonNetworking",
        "InsteonProtocol",
        .product(name: "Crypto", package: "swift-crypto")
      ],
      path: "Packages/InsteonDeviceCatalog/Sources/InsteonDeviceCatalog",
      resources: [.copy("Resources/catalog.json"), .copy("Resources/manifest.json")],
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonDeviceCatalogTests",
      dependencies: [
        "InsteonDeviceCatalog",
        "InsteonNetworking",
        "InsteonProtocol",
        .product(name: "Crypto", package: "swift-crypto")
      ],
      path: "Packages/InsteonDeviceCatalog/Tests/InsteonDeviceCatalogTests",
      swiftSettings: memberImportVisibility
    ),

    .target(
      name: "InsteonNotifications",
      dependencies: ["InsteonDeviceCatalog", "InsteonProtocol"],
      path: "Packages/InsteonNotifications/Sources/InsteonNotifications",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonNotificationsTests",
      dependencies: ["InsteonNotifications", "InsteonDeviceCatalog", "InsteonProtocol"],
      path: "Packages/InsteonNotifications/Tests/InsteonNotificationsTests",
      swiftSettings: memberImportVisibility
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
      path: "Packages/InsteonCore/Sources/InsteonCore",
      swiftSettings: memberImportVisibility
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
        "InsteonNetworking",
        "InsteonProtocol",
        "InsteonTestSupport"
      ],
      path: "Packages/InsteonCore/Tests/InsteonCoreTests",
      swiftSettings: memberImportVisibility
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
      path: "Packages/InsteonCLI/Tests/InsteonCLISupportTests",
      swiftSettings: memberImportVisibility
    ),

    // Test doubles shared by the test targets. Not products. InsteonTestSupport has the clock,
    // the scripted modem connection and the HTTP stub; InsteonLinkingTestSupport has the
    // in-memory modem, which is a LinkingModem, so the tests of the layers below InsteonLinking
    // don't link it.
    .target(
      name: "InsteonTestSupport",
      dependencies: ["InsteonModem", "InsteonNetworking"],
      path: "Packages/InsteonTestSupport/Sources/InsteonTestSupport",
      swiftSettings: memberImportVisibility
    ),
    .testTarget(
      name: "InsteonTestSupportTests",
      dependencies: ["InsteonTestSupport"],
      path: "Packages/InsteonTestSupport/Tests/InsteonTestSupportTests",
      swiftSettings: memberImportVisibility
    ),
    .target(
      name: "InsteonLinkingTestSupport",
      dependencies: ["InsteonLinking", "InsteonModem", "InsteonProtocol"],
      path: "Packages/InsteonTestSupport/Sources/InsteonLinkingTestSupport",
      swiftSettings: memberImportVisibility
    )
  ]
)
