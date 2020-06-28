// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "InsteonApiClient",
  products: [
    // Products define the executables and libraries produced by a package, and make them visible to other packages.
    .library(
      name: "InsteonApiClient",
      targets: ["InsteonApiClient"]),
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(
      url: "https://github.com/brandtdaniels/RequestClient",
      from: "0.1.0"
    ),
    .package(
      path: "../AuthClient"
    ),
    .package(
      url: "https://github.com/kishikawakatsumi/KeychainAccess",
      .upToNextMajor(from: "4.2.0")
    )
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages which this package depends on.
    .target(
      name: "InsteonApiClient",
      dependencies: ["AuthClient", "KeychainAccess", "RequestClient"]),
    .testTarget(
      name: "InsteonApiClientTests",
      dependencies: ["InsteonApiClient"]),
  ]
)
