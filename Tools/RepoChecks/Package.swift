// swift-tools-version: 6.3

import PackageDescription

// The repository's checks, as a package of their own so the root package's libraries, its
// explicit-import check and the iOS scheme never see it.
let package = Package(
  name: "RepoChecks",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "repo-check", targets: ["repo-check"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2"))
  ],
  targets: [
    // Reading files as the checks need to, and the output conventions of a check.
    .target(name: "RepoCheckSupport"),
    // One type per check.
    .target(name: "RepoChecks", dependencies: ["RepoCheckSupport"]),
    // The command: one subcommand per check.
    .executableTarget(
      name: "repo-check",
      dependencies: [
        "RepoChecks",
        "RepoCheckSupport",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .testTarget(name: "RepoCheckSupportTests", dependencies: ["RepoCheckSupport"]),
    .testTarget(name: "RepoCheckTests", dependencies: ["RepoChecks", "RepoCheckSupport"])
  ]
)
