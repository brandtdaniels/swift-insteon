import Foundation

/// What a comparison found.
public struct EquivalenceReport: Equatable, Sendable {
  /// A run of the two checks on one tree that didn't match.
  public struct Difference: Equatable, Sendable {
    public var round: Int
    public var mutant: Int
    public var description: String
    public var streams: [String]
    public var oracle: CheckOutput
    public var candidate: CheckOutput
  }

  /// The results of one round: the unmutated repository, or a set of mutants from one seed.
  public struct Round: Equatable, Sendable {
    public var index: Int
    public var seed: UInt64?
    public var compared = 0
    public var matchingCrashes = 0
    /// The runs where the oracle reported a finding, so the check had something to get right.
    public var withFindings = 0
    public var differences: [Difference] = []
  }

  public var checkName: String
  public var rounds: [Round] = []

  public init(checkName: String) {
    self.checkName = checkName
  }

  /// The number of runs compared, the unmutated repository included.
  public var compared: Int { rounds.reduce(0) { $0 + $1.compared } }

  /// The number of runs where Python and Swift differed.
  public var differences: Int { rounds.reduce(0) { $0 + $1.differences.count } }

  /// The number of runs where Python crashed and Swift stopped with the same status.
  public var matchingCrashes: Int { rounds.reduce(0) { $0 + $1.matchingCrashes } }

  /// The number of runs where Python reported a finding.
  public var withFindings: Int { rounds.reduce(0) { $0 + $1.withFindings } }

  /// The report as text, with each difference shown in full.
  public func render() -> String {
    var lines = ["Transitional equivalence of repo-check \(checkName) with its Python script, the oracle."]

    for round in rounds {
      let label = round.seed.map { "round \(round.index) (seed \($0))" } ?? "the repository"
      lines.append("\(label): \(round.compared) compared, \(round.differences.count) differences")
      for difference in round.differences {
        lines.append("  difference in round \(difference.round), mutant \(difference.mutant): \(difference.description)")
        lines.append("  differs in: \(difference.streams.joined(separator: ", "))")
        lines.append(contentsOf: Self.indented("python", difference.oracle))
        lines.append(contentsOf: Self.indented("swift", difference.candidate))
      }
    }

    lines.append(
      "Total: \(rounds.count - 1) rounds, \(compared) compared (\(withFindings) with findings), \(differences) differences, \(matchingCrashes) crashes with matching status."
    )
    return lines.joined(separator: "\n")
  }

  private static func indented(_ label: String, _ output: CheckOutput) -> [String] {
    var lines = ["    \(label): status \(output.status)"]
    for (name, text) in [("stdout", output.outputText), ("stderr", output.errorText)] where !text.isEmpty {
      lines.append("    \(label) \(name):")
      lines.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: false).prefix(12).map { "      \($0)" })
    }
    return lines
  }
}
