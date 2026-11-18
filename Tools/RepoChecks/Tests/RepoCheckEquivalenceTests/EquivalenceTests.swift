import Foundation
import RepoCheckSupport
import Testing

@testable import RepoCheckEquivalence

/// A check that answers from a closure over the tree's workflow file, with no process.
private struct StubCheck: CheckRunning {
  let answer: (URL) throws -> CheckOutput

  func run(in tree: URL) throws -> CheckOutput {
    try answer(tree)
  }
}

private func output(_ status: Int32, _ out: String = "", _ err: String = "") -> CheckOutput {
  CheckOutput(status: status, standardOutput: Data(out.utf8), standardError: Data(err.utf8))
}

private func repository(workflow: String = "jobs:\n  a:\n    timeout-minutes: 1\n    steps:\n      - uses: x/y@v1\n") throws -> ScratchDirectory {
  let directory = try ScratchDirectory()
  try directory.write(workflow, to: ".github/workflows/ci.yml")
  try directory.write("keep", to: "Sources/a.swift")
  try directory.write("junk", to: ".build/x")
  try directory.write("junk", to: "__pycache__/x.pyc")
  return directory
}

@Suite("Comparison")
struct ComparisonTests {
  @Test("identical outputs are identical")
  func identical() {
    #expect(Comparison(oracle: output(0, "a"), candidate: output(0, "a")) == .identical)
  }

  @Test("names each stream that differs")
  func names() {
    #expect(Comparison(oracle: output(1, "a", "x"), candidate: output(0, "b", "y")) == .differs(["status", "stdout", "stderr"]))
    #expect(Comparison(oracle: output(0, "a"), candidate: output(0, "a", "warn")) == .differs(["stderr"]))
  }

  @Test("a Python traceback matches a Swift error with the same status and output")
  func crash() {
    let python = output(1, "", "Traceback (most recent call last):\n  File x\nIsADirectoryError")
    #expect(Comparison(oracle: python, candidate: output(1, "", "Error: x")) == .matchingCrash)
    #expect(Comparison(oracle: python, candidate: output(0, "", "Error: x")) == .differs(["status", "stderr"]))
    #expect(Comparison(oracle: python, candidate: output(1)).isDifference)
  }
}

@Suite("SeededGenerator")
struct SeededGeneratorTests {
  @Test("gives the same numbers for the same seed and others for another")
  func deterministic() {
    var a = SeededGenerator(seed: 7)
    var b = SeededGenerator(seed: 7)
    var c = SeededGenerator(seed: 8)

    #expect((0..<5).map { _ in a.next() } == (0..<5).map { _ in b.next() })
    #expect(a.next() != c.next())
  }
}

@Suite("MutableTree")
struct MutableTreeTests {
  @Test("copies the repository without build products, caches or version control")
  func copies() throws {
    let source = try repository()
    let tree = try MutableTree(copying: source.url)

    #expect(try tree.files(under: ".github/workflows") == [".github/workflows/ci.yml"])
    #expect(FileManager.default.fileExists(atPath: tree.root.appendingPathComponent("Sources/a.swift").path))
    #expect(!FileManager.default.fileExists(atPath: tree.root.appendingPathComponent(".build").path))
    #expect(!FileManager.default.fileExists(atPath: tree.root.appendingPathComponent("__pycache__").path))
  }

  @Test("applies edits and takes them back")
  func appliesAndRestores() throws {
    let source = try repository()
    let tree = try MutableTree(copying: source.url)
    let original = try tree.read(".github/workflows/ci.yml")

    let undo = try tree.apply([
      .write(path: ".github/workflows/ci.yml", data: Data("x".utf8)),
      .write(path: ".github/workflows/new.yml", data: Data("y".utf8)),
      .makeDirectory(path: ".github/workflows/dir.yml"),
      .remove(path: "Sources/a.swift")
    ])

    #expect(try tree.read(".github/workflows/ci.yml") == Data("x".utf8))
    #expect(try tree.files(under: ".github/workflows") == [".github/workflows/ci.yml", ".github/workflows/new.yml"])

    try tree.restore(undo)

    #expect(try tree.read(".github/workflows/ci.yml") == original)
    #expect(try tree.files(under: ".github/workflows") == [".github/workflows/ci.yml"])
    #expect(!FileManager.default.fileExists(atPath: tree.root.appendingPathComponent(".github/workflows/dir.yml").path))
    #expect(try tree.read("Sources/a.swift") == Data("keep".utf8))
  }
}

@Suite("ProcessCheckRunner")
struct ProcessCheckRunnerTests {
  @Test("keeps the status and both streams of a process that runs in the tree")
  func capturesOutput() throws {
    let tree = try ScratchDirectory()
    let runner = ProcessCheckRunner(command: ["/bin/sh", "-c", "pwd; echo oops >&2; exit 3", "sh"])

    let result = try runner.run(in: tree.url)

    #expect(result.status == 3)
    #expect(result.errorText == "oops\n")
    #expect(URL(fileURLWithPath: result.outputText.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath().path
      == tree.url.resolvingSymlinksInPath().path)
  }

  @Test("refuses an executable that isn't there")
  func missingExecutable() throws {
    let runner = ProcessCheckRunner(command: ["/nonexistent/repo-check"])

    #expect(throws: ProcessLaunchError.self) { try runner.run(in: try ScratchDirectory().url) }
  }

  @Test("runs the Python oracle as the interpreter, with the flags and the script in the tree")
  func pythonOracleCommand() throws {
    let tree = try ScratchDirectory()
    let stub = try ScratchDirectory()
    try stub.write("#!/bin/sh\nfor argument in \"$@\"; do echo \"$argument\"; done\n", to: "python3")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.url(for: "python3").path)
    let runner = PythonOracle.runner(interpreter: [stub.url(for: "python3").path], script: "Scripts/check-x.py") {
      ["--root", $0.path]
    }

    let lines = try runner.run(in: tree.url).outputText.split(separator: "\n").map(String.init)

    #expect(lines == ["-B", "-X", "utf8", tree.url.appendingPathComponent("Scripts/check-x.py").path, "--root", tree.url.path])
  }
}

@Suite("EquivalenceRun")
struct EquivalenceRunTests {
  private func subject(candidate: @escaping (URL) throws -> CheckOutput) -> EquivalenceSubject {
    EquivalenceSubject(
      name: "workflows",
      oracle: StubCheck { _ in output(0, "ok\n") },
      candidate: StubCheck(answer: candidate),
      makeMutants: { try WorkflowMutations(tree: $0) }
    )
  }

  @Test("reports no difference when the two agree, in every round")
  func agrees() throws {
    let run = EquivalenceRun(subject: subject { _ in output(0, "ok\n") }, rounds: 3, mutantsPerRound: 5, seed: 1)

    let source = try repository()
    let report = try run.run(repository: source.url)

    #expect(report.rounds.count == 4)
    #expect(report.compared == 16)
    #expect(report.differences == 0)
  }

  @Test("reports a difference with the mutant that shows it")
  func differs() throws {
    let run = EquivalenceRun(
      subject: subject { tree in
        let text = String(decoding: (try? Data(contentsOf: tree.appendingPathComponent(".github/workflows/ci.yml"))) ?? Data(), as: UTF8.self)
        return output(0, text.contains("uses: x/y@v1") ? "ok\n" : "changed\n")
      },
      rounds: 2,
      mutantsPerRound: 20,
      seed: 5
    )

    let source = try repository()
    let report = try run.run(repository: source.url)

    #expect(report.differences > 0)
    #expect(report.rounds[0].differences.isEmpty)
    #expect(report.render().contains("differs in: stdout"))
  }

  @Test("makes the same mutants from the same seed")
  func reproducible() throws {
    let source = try repository()
    let tree = try MutableTree(copying: source.url)
    let mutations = try WorkflowMutations(tree: tree)

    func descriptions(seed: UInt64) throws -> [String] {
      var generator = SeededGenerator(seed: seed)
      return try (0..<30).map { _ in try mutations.makeMutant(in: tree, using: &generator).description }
    }

    #expect(try descriptions(seed: 3) == descriptions(seed: 3))
    #expect(try descriptions(seed: 3) != descriptions(seed: 4))
  }

  @Test("leaves the copy as it found it after each mutant")
  func restores() throws {
    let source = try repository()
    let tree = try MutableTree(copying: source.url)
    let mutations = try WorkflowMutations(tree: tree)
    let before = try tree.read(".github/workflows/ci.yml")
    var generator = SeededGenerator(seed: 11)

    for _ in 0..<50 {
      let undo = try tree.apply(try mutations.makeMutant(in: tree, using: &generator).edits)
      try tree.restore(undo)
    }

    #expect(try tree.read(".github/workflows/ci.yml") == before)
    #expect(try tree.files(under: ".github/workflows") == [".github/workflows/ci.yml"])
  }
}
