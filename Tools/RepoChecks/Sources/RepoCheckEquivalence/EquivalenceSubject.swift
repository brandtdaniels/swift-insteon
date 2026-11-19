import Foundation
import RepoCheckSupport

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

  /// Which entries the tree that mutants are applied to keeps. The unmutated repository is
  /// always compared whole; a smaller tree makes the mutants cheaper to run.
  public let mutationCorpus: (SourceEntry) -> Bool

  /// Runners of the check with `--update`, when its written file is compared too.
  public internal(set) var updateRunners: (oracle: CheckRunning, candidate: CheckRunning)?

  public init(
    name: String,
    oracle: CheckRunning,
    candidate: CheckRunning,
    mutationCorpus: @escaping (SourceEntry) -> Bool = { _ in true },
    makeMutants: @escaping (MutableTree) throws -> MutantGenerating
  ) {
    self.mutationCorpus = mutationCorpus
    self.name = name
    self.oracle = oracle
    self.candidate = candidate
    self.makeMutants = makeMutants
  }
}

/// The checks that can be compared.
public enum EquivalenceSubjects {
  /// The names of the checks, in the order they are ported.
  public static let names = ["workflows", "terms", "cli-thin", "concurrency"]

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
    case "terms":
      return EquivalenceSubject(
        name: name,
        oracle: PythonOracle.runner(interpreter: interpreter, script: "Scripts/check-terms.py"),
        candidate: ProcessCheckRunner(command: [repoCheck, name]),
        mutationCorpus: { sample($0, every: 12) },
        makeMutants: { tree in
          let paths = try tree.filesWithSuffixes([".swift", ".md"])
          return try TextFileMutations(
            tree: tree,
            paths: paths,
            operators: TermsMutations.operators,
            addDirectory: "Docs",
            addNames: ["Extra.md", "Extra.swift", "CONVENTIONS.md", "notes.txt", ".md", "x.MD", "dir.md"]
          )
        }
      )
    case "cli-thin":
      return EquivalenceSubject(
        name: name,
        oracle: PythonOracle.runner(interpreter: interpreter, script: "Scripts/check-cli-thin.py"),
        candidate: ProcessCheckRunner(command: [repoCheck, name]),
        mutationCorpus: { $0.components.first != "Packages" || $0.components.prefix(3) == ["Packages", "InsteonCLI", "Sources"] || $0.components.count < 3 },
        makeMutants: { tree in
          let sources = try tree.filesWithSuffixes([".swift"]).filter { $0.hasPrefix("Packages/InsteonCLI/Sources/") }
          return WeightedMutations([
            (try TextFileMutations(tree: tree, paths: sources, operators: CLIThinMutations.sourceOperators), 8),
            (try TextFileMutations(tree: tree, paths: ["Scripts/check-cli-thin-allowlist.txt"], operators: CLIThinMutations.allowListOperators), 2)
          ])
        }
      ).comparingUpdates(
        oracle: UpdatingRunner(
          base: PythonOracle.runner(interpreter: interpreter, script: "Scripts/check-cli-thin.py") { _ in ["--update"] },
          file: "Scripts/check-cli-thin-allowlist.txt"
        ),
        candidate: UpdatingRunner(
          base: ProcessCheckRunner(command: [repoCheck, name, "--update"]),
          file: "Scripts/check-cli-thin-allowlist.txt"
        )
      )
    case "concurrency":
      let file = "Scripts/check-concurrency-allowlist.txt"
      return EquivalenceSubject(
        name: name,
        oracle: PythonOracle.runner(interpreter: interpreter, script: "Scripts/check-concurrency.py"),
        candidate: ProcessCheckRunner(command: [repoCheck, name]),
        mutationCorpus: { sampleSources($0, every: 6) },
        makeMutants: { tree in
          let sources = try tree.filesWithSuffixes([".swift"]).filter { $0.hasPrefix("Packages/") && $0.contains("/Sources/") }
          return WeightedMutations([
            (try TextFileMutations(tree: tree, paths: sources, operators: ConcurrencyMutations.sourceOperators), 8),
            (try TextFileMutations(tree: tree, paths: [file], operators: ConcurrencyMutations.allowListOperators), 2)
          ])
        }
      ).comparingUpdates(
        oracle: UpdatingRunner(
          base: PythonOracle.runner(interpreter: interpreter, script: "Scripts/check-concurrency.py") { _ in ["--update"] },
          file: file
        ),
        candidate: UpdatingRunner(base: ProcessCheckRunner(command: [repoCheck, name, "--update"]), file: file)
      )
    default:
      return nil
    }
  }
}

/// Keeps what the Python scripts need to run, and one in `every` of the other files, chosen by
/// their paths so the same ones stay on every run.
func sample(_ entry: SourceEntry, every: Int) -> Bool {
  if entry.components.first == "Scripts" || entry.components.first == ".github" || entry.isDirectory {
    return true
  }
  let name = entry.components.last!
  if name == "CONVENTIONS.md" || name == "README.md" {
    return true
  }
  let weight = entry.relativePath.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
  return weight % every == 0
}

extension EquivalenceSubject {
  /// A copy of the subject that also compares the runs of the check with `--update`.
  func comparingUpdates(oracle: CheckRunning, candidate: CheckRunning) -> EquivalenceSubject {
    var copy = self
    copy.updateRunners = (oracle, candidate)
    return copy
  }
}

/// Keeps what the Python scripts need to run, every file the allow-lists name, and one in
/// `every` of the Swift sources under `Packages`, chosen by their paths.
func sampleSources(_ entry: SourceEntry, every: Int) -> Bool {
  if entry.components.first != "Packages" || entry.isDirectory {
    return true
  }
  if entry.components.contains("Sources"), entry.components.last!.hasSuffix(".swift") {
    return sample(entry, every: every)
  }
  return false
}
