// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "swift-insteon",
  products: [
    .library(name: "InsteonMessage", targets: ["InsteonMessage"])
  ],
  targets: [
    .target(
      name: "InsteonMessage",
      path: "Packages/InsteonMessage/Sources/InsteonMessage"
    ),
    .testTarget(
      name: "InsteonMessageTests",
      dependencies: ["InsteonMessage"],
      path: "Packages/InsteonMessage/Tests/InsteonMessageTests"
    )
  ]
)
