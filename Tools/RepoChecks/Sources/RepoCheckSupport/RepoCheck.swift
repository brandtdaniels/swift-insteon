import Foundation

/// A check of the repository, run from a root directory.
public protocol RepoCheck {
  /// Runs the check on the repository at the root, reports to the console and says how it ended.
  func run(in root: URL, console: Console) throws -> CheckStatus
}
