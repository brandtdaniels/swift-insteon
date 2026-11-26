// swift-tools-version: 6.3

import PackageDescription

// The shared screens and view models of the Insteon app for iPhone, iPad and Mac. They call
// libraries and present the results; they hold no protocol, scene or connection logic.
// `repo-check app-thin` holds the imports to the list below.
let package = Package(
  name: "InsteonApp",
  platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .visionOS(.v1)],
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
        .product(name: "InsteonService", package: "swift-insteon")
      ]
    ),
    .testTarget(
      name: "InsteonAppUITests",
      dependencies: [
        "InsteonAppUI",
        .product(name: "InsteonCore", package: "swift-insteon"),
        .product(name: "InsteonService", package: "swift-insteon")
      ]
    )
  ]
)
