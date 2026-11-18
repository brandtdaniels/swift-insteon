import Foundation

/// A check that has a Python script and a Swift subcommand to compare.
public struct EquivalenceSubject {
  /// The check's name, as `repo-check` spells the subcommand.
  public let name: String

  /// Runs the Python script. It is the oracle: where the two differ, the Swift is wrong.
  public let oracle: CheckRunning

  /// Runs the Swift subcommand.
  public let candidate: CheckRunning

  /// Makes the generator of mutants for a tree, which is read once before any mutant applies.
  public let makeMutants: (MutableTree) throws -> MutantGenerating

  public init(
    name: String,
    oracle: CheckRunning,
    candidate: CheckRunning,
    makeMutants: @escaping (MutableTree) throws -> MutantGenerating
  ) {
    self.name = name
    self.oracle = oracle
    self.candidate = candidate
    self.makeMutants = makeMutants
  }
}

/// The checks that can be compared.
public enum EquivalenceSubjects {
  /// The names of the checks, in the order they are ported.
  public static let names = ["workflows"]

  /// The subject for the named check, or nil if the name isn't one.
  ///
  /// - Parameters:
  ///   - interpreter: The Python command, such as `["/usr/bin/env", "python3"]`.
  ///   - repoCheck: The path of the `repo-check` executable.
  public static func subject(named name: String, interpreter: [String], repoCheck: String) -> EquivalenceSubject? {
    switch name {
    case "workflows":
      return EquivalenceSubject(
        name: name,
        oracle: PythonOracle.runner(interpreter: interpreter, script: "Scripts/check-workflows.py") {
          ["--root", $0.path]
        },
        candidate: ProcessCheckRunner(command: [repoCheck, name]) { ["--root", $0.path] },
        makeMutants: { try WorkflowMutations(tree: $0) }
      )
    default:
      return nil
    }
  }
}
