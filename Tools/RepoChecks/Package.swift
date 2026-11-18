// swift-tools-version: 6.3

import PackageDescription

// The repository's checks, as a package of their own so the root package's libraries, its
// explicit-import check and the iOS scheme never see it.
let package = Package(
  name: "RepoChecks",
  platforms: [.macOS(.v13)],
  targets: [
    // Reading files the way the Python scripts did, and the output conventions of a check.
    .target(name: "RepoCheckSupport"),
    .testTarget(name: "RepoCheckSupportTests", dependencies: ["RepoCheckSupport"])
  ]
)
