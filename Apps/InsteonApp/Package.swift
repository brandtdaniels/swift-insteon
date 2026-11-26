// swift-tools-version: 6.3

import PackageDescription

// The shared screens and view models of the Insteon app for iPhone, iPad and Mac. They call
// libraries and present the results; they hold no protocol, scene or connection logic.
// `repo-check app-thin` holds the imports to the libraries below and the frameworks that host an interface.
let package = Package(
  name: "InsteonApp",
  // tvOS and visionOS join when a change builds them in CI.
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "InsteonAppUI", targets: ["InsteonAppUI"])
  ],
  dependencies: [
    .package(name: "swift-insteon", path: "../..")
  ],
  targets: [
    .target(
      name: "InsteonAppUI",
      dependencies: [
        .product(name: "InsteonCore", package: "swift-insteon"),
        .product(name: "InsteonService", package: "swift-insteon"),
        .product(name: "InsteonClient", package: "swift-insteon"),
        .product(name: "InsteonDemo", package: "swift-insteon")
      ]
    ),
    .testTarget(
      name: "InsteonAppUITests",
      dependencies: [
        "InsteonAppUI",
        .product(name: "InsteonDemo", package: "swift-insteon"),
        .product(name: "InsteonClient", package: "swift-insteon"),
        .product(name: "InsteonCore", package: "swift-insteon"),
        .product(name: "InsteonService", package: "swift-insteon")
      ]
    )
  ]
)
