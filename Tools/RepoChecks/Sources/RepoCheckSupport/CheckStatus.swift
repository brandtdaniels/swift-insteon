/// How a check ended, which is the command's exit status.
///
/// A check that finds nothing exits with 0 and one that finds a problem exits with 1, as the
/// scripts did. A check that can't run, because a file is unreadable, throws instead.
public enum CheckStatus: Int32, Equatable, Sendable {
  case passed = 0
  case failed = 1

  /// Failed if there is anything to report.
  public init(findings: [String]) {
    self = findings.isEmpty ? .passed : .failed
  }
}
