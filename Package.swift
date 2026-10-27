// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "swift-insteon",
  products: [
    .library(name: "InsteonProtocol", targets: ["InsteonProtocol"])
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
    )
  ]
)
