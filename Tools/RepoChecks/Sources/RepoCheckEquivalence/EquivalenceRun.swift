import Foundation
import RepoCheckSupport

/// Compares a check's Python script with its Swift subcommand on a copy of the repository and
/// on seeded mutants of it.
///
/// Round 0 is the repository as it is. Each later round makes `mutantsPerRound` mutants from
/// the seed `seed + round`, so a difference reproduces from the numbers in the report. Each
/// mutant is applied to the copy, both checks run on it, and it is taken back.
public struct EquivalenceRun {
  public let subject: EquivalenceSubject
  public let rounds: Int
  public let mutantsPerRound: Int
  public let seed: UInt64

  public init(subject: EquivalenceSubject, rounds: Int, mutantsPerRound: Int, seed: UInt64) {
    self.subject = subject
    self.rounds = rounds
    self.mutantsPerRound = mutantsPerRound
    self.seed = seed
  }

  /// Runs the comparison on a copy of the repository and reports each round to `progress`.
  public func run(repository: URL, progress: (String) -> Void = { _ in }) throws -> EquivalenceReport {
    var report = EquivalenceReport(checkName: subject.name)

    var baseline = EquivalenceReport.Round(index: 0, seed: nil)
    let whole = try MutableTree(copying: repository)
    try subject.prepare(whole.root)
    try compare(in: whole, round: &baseline, mutant: 0, description: "the repository")
    report.rounds.append(baseline)
    progress("the repository: \(baseline.differences.count) differences")

    let tree = try MutableTree(copying: repository, including: subject.mutationCorpus)
    try subject.prepare(tree.root)
    let mutants = try subject.makeMutants(tree)

    for index in 1...max(rounds, 1) where index <= rounds {
      let roundSeed = seed &+ UInt64(index)
      var generator = SeededGenerator(seed: roundSeed)
      var round = EquivalenceReport.Round(index: index, seed: roundSeed)

      for number in 1...max(mutantsPerRound, 1) where number <= mutantsPerRound {
        let mutant = try mutants.makeMutant(in: tree, using: &generator)
        let undo = try tree.apply(mutant.edits)
        defer { try? tree.restore(undo) }
        try compare(in: tree, round: &round, mutant: number, description: mutant.description)
      }

      report.rounds.append(round)
      progress("round \(index) (seed \(roundSeed)): \(round.compared) compared, \(round.differences.count) differences")
    }

    return report
  }

  private func compare(
    in tree: MutableTree,
    round: inout EquivalenceReport.Round,
    mutant: Int,
    description: String
  ) throws {
    let pairs = [(subject.oracle, subject.candidate)] + (subject.updateRunners.map { [($0.oracle, $0.candidate)] } ?? [])
    for (index, pair) in pairs.enumerated() {
      try compareOne(oracle: pair.0, candidate: pair.1, in: tree, round: &round, mutant: mutant, description: index == 0 ? description : description + " (second run)")
    }
  }

  private func compareOne(
    oracle oracleRunner: CheckRunning,
    candidate candidateRunner: CheckRunning,
    in tree: MutableTree,
    round: inout EquivalenceReport.Round,
    mutant: Int,
    description: String
  ) throws {
    let oracle = try oracleRunner.run(in: tree.root)
    let candidate = try candidateRunner.run(in: tree.root)
    round.compared += 1
    if oracle.status != 0 {
      round.withFindings += 1
    }

    switch Comparison(oracle: oracle, candidate: candidate) {
    case .identical:
      break
    case .matchingCrash:
      round.matchingCrashes += 1
    case .differs(let streams):
      round.differences.append(
        EquivalenceReport.Difference(
          round: round.index,
          mutant: mutant,
          description: description,
          streams: streams,
          oracle: oracle,
          candidate: candidate
        )
      )
    }
  }
}
