import ArgumentParser
import Foundation
import RepoCheckEquivalence

/// Development commands for the move from the Python scripts to `repo-check`. Deleted with
/// the Python.
@main
struct RepoCheckDev: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "repo-check-dev",
    abstract: "Transitional tools for checking repo-check against the Python scripts it replaces.",
    subcommands: [EquivalenceCommand.self]
  )
}

struct EquivalenceCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "equivalence",
    abstract: "Runs a check's Python script and its repo-check subcommand on a copy of the repository and on mutants of it.",
    discussion: "Python is the oracle. Exits with status 1 if any run differs in status, standard output or standard error."
  )

  @Option(help: "The check to compare: \(EquivalenceSubjects.names.joined(separator: ", ")).")
  var check: String

  @Option(help: "The repository to copy. The current directory by default.")
  var repository: String?

  @Option(help: "The repo-check executable. The one beside this executable by default.")
  var repoCheck: String?

  @Option(help: "The Python command, with its arguments.")
  var python: [String] = ["/usr/bin/env", "python3"]

  @Option(help: "The number of rounds of mutants.")
  var rounds = 10

  @Option(help: "The number of mutants in each round.")
  var mutants = 100

  @Option(help: "The seed of the first round. Round N uses seed + N.")
  var seed: UInt64 = 0

  func run() throws {
    let root = URL(fileURLWithPath: repository ?? FileManager.default.currentDirectoryPath, isDirectory: true)
    let executable = repoCheck ?? Self.siblingRepoCheck()

    guard let subject = EquivalenceSubjects.subject(named: check, interpreter: python, repoCheck: executable) else {
      throw ValidationError("There is no check named \(check). The checks are \(EquivalenceSubjects.names.joined(separator: ", ")).")
    }

    let run = EquivalenceRun(subject: subject, rounds: rounds, mutantsPerRound: mutants, seed: seed)
    let report = try run.run(repository: root) { print($0) }

    print(report.render())

    if report.differences > 0 {
      throw ExitCode.failure
    }
  }

  private static func siblingRepoCheck() -> String {
    let own = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return own.deletingLastPathComponent().appendingPathComponent("repo-check").path
  }
}
