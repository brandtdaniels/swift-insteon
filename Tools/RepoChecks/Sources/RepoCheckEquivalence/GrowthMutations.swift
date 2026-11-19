import Foundation

/// Mutants aimed at `allowlist-growth`: the allow-lists with entries added, repeated, reworded,
/// reordered and removed, compared with the committed ones.
public enum GrowthMutations {
  static let lists = [
    "Scripts/check-cli-thin-allowlist.txt", "Scripts/check-concurrency-allowlist.txt",
    "Scripts/check-credentials-allowlist.txt", "Scripts/check-device-neutral-allowlist.txt"
  ]

  static let operators: [TextOperator] =
    [
      TextOperator("addLine") { lines, generator in
        let line = [
          "insteon/A.swift\tengine\tengine == .i2cs", "#comment", "+plus", "x", "a\tb", "a\tb\tc", "a\tb\tc\td", "a\tb\tc\tother reason",
          "\t", "a\t", "\ta", "a\tb\tc\td\te", " ", "+", "++x", "#"
        ].randomElement(using: &generator)!
        lines.insert(line, at: Int.random(in: 0...lines.count, using: &generator))
        return true
      },
      TextOperator("rewordLastColumn") { lines, generator in
        guard let index = lines.randomIndex(using: &generator, where: { $0.contains("\t") && !$0.hasPrefix("#") }) else { return false }
        var columns = lines[index].components(separatedBy: "\t")
        columns[columns.count - 1] = ["", "another reason", "r\u{E9}ason"].randomElement(using: &generator)!
        lines[index] = columns.joined(separator: "\t")
        return true
      },
      TextOperator("changeKey") { lines, generator in
        guard let index = lines.randomIndex(using: &generator, where: { $0.contains("\t") && !$0.hasPrefix("#") }) else { return false }
        var columns = lines[index].components(separatedBy: "\t")
        columns[Int.random(in: 0..<min(columns.count, 3), using: &generator)] += ["x", "\u{301}", " "].randomElement(using: &generator)!
        lines[index] = columns.joined(separator: "\t")
        return true
      },
      TextOperator("sortLines") { lines, generator in
        lines.shuffle(using: &generator)
        return true
      }
    ] + CommonOperators.all

  static func prepare(_ tree: URL) throws {
    let identity = ["-c", "user.name=Check", "-c", "user.email=check@example.invalid"]
    func git(_ arguments: [String]) throws {
      let result = try ProcessCheckRunner(command: ["/usr/bin/env", "git"] + identity + arguments).run(in: tree)
      guard result.status == 0 else {
        throw ProcessLaunchError(command: arguments, reason: result.errorText)
      }
    }
    try git(["init", "-q"])
    try git(["add", "-A"])
    try git(["commit", "-q", "-m", "base"])
    try git(["update-ref", "refs/remotes/origin/main", "HEAD"])
    // A base that has none of the lists.
    try git(["update-ref", "refs/remotes/origin/empty", try emptyCommit(tree, identity: identity)])
  }

  private static func emptyCommit(_ tree: URL, identity: [String]) throws -> String {
    let empty = try ProcessCheckRunner(command: ["/usr/bin/env", "git", "hash-object", "-w", "-t", "tree", "/dev/null"]).run(in: tree)
    let emptyTree = String(decoding: empty.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let result = try ProcessCheckRunner(
      command: ["/usr/bin/env", "git"] + identity + ["commit-tree", "-m", "empty", emptyTree]
    ).run(in: tree)
    return String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func subject(repoCheck: String) throws -> EquivalenceSubject {
    let scratch = try ScratchDirectoryHolder.make()
    try scratch.write(LegacyGrowthScript.text, to: "legacy-growth.sh")
    let script = scratch.url(for: "legacy-growth.sh").path

    var subject = EquivalenceSubject(
      name: "allowlist-growth",
      oracle: ProcessCheckRunner(command: ["/bin/bash", script, "main"]),
      candidate: ProcessCheckRunner(command: [repoCheck, "allowlist-growth", "--base", "origin/main"]),
      mutationCorpus: { entry in entry.isDirectory || lists.contains(entry.relativePath) },
      makeMutants: { tree in try TextFileMutations(tree: tree, paths: lists, operators: operators) }
    )
    subject.prepare = prepare
    return subject.comparingUpdates(
      oracle: ProcessCheckRunner(command: ["/bin/bash", script, "empty"]),
      candidate: ProcessCheckRunner(command: [repoCheck, "allowlist-growth", "--base", "origin/empty"])
    )
  }
}
