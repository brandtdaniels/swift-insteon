// swift-tools-version: 6.3

import PackageDescription

// The repository's checks, as a package of their own so the root package's libraries, its
// explicit-import check and the iOS scheme never see it.
let package = Package(
  name: "RepoChecks",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "repo-check", targets: ["repo-check"]),
    .executable(name: "repo-check-dev", targets: ["repo-check-dev"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.8.2"))
  ],
  targets: [
    // Reading files the way the Python scripts did, and the output conventions of a check.
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
    // Transitional: compares each check with the Python script it replaces. Deleted with the
    // Python.
    .target(name: "RepoCheckEquivalence", dependencies: ["RepoCheckSupport"]),
    .executableTarget(
      name: "repo-check-dev",
      dependencies: [
        "RepoCheckEquivalence",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .testTarget(name: "RepoCheckSupportTests", dependencies: ["RepoCheckSupport"]),
    .testTarget(name: "RepoCheckTests", dependencies: ["RepoChecks", "RepoCheckSupport"]),
    .testTarget(name: "RepoCheckEquivalenceTests", dependencies: ["RepoCheckEquivalence", "RepoCheckSupport"])
  ]
)
