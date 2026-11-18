import Foundation
import RepoCheckSupport

/// Checks that the GitHub Actions workflows pin what they run and bound how long they run.
///
/// A tag such as `actions/checkout@v4` or `swift:6.3.3` can be moved to point at other code, so:
///
/// - each `uses:` names an action by a full 40-digit commit SHA, followed by a comment with the
///   version it is, such as `actions/checkout@<sha> # v4.4.0`; a local action, `./...`, is fine;
/// - each `container:` or `image:` names its image by digest, `name:tag@sha256:<64 digits>`;
/// - and each job sets `timeout-minutes`, so a job that hangs fails in minutes rather than after
///   GitHub's six-hour limit.
///
/// It reads `.github/workflows/*.yml` and `*.yaml` under the root line by line rather than as
/// YAML, and reports each line that breaks a rule.
public struct WorkflowsCheck: RepoCheck {
  public init() {}

  /// What the check prints when it finds nothing.
  public static let successMessage = "Every action and image is pinned, and every job has a time limit."

  public func run(in root: URL, console: Console) throws -> CheckStatus {
    let found = try problems(in: root)

    console.write(found.isEmpty ? Self.successMessage : found.joined(separator: "\n"))

    return CheckStatus(findings: found)
  }

  /// Every problem in the workflows under the root, one message each.
  public func problems(in root: URL) throws -> [String] {
    var found: [String] = []

    for name in try workflowNames(in: root) {
      let text = try TextFile.read(workflows(in: root).appendingPathComponent(name))
      found.append(contentsOf: problems(inText: text, named: ".github/workflows/\(name)"))
    }

    return found
  }

  /// Each problem in one workflow's text. The name is how a message calls the file.
  func problems(inText text: String, named relative: String) -> [String] {
    let lines = PythonText.splitLines(text)
    var found: [String] = []

    let patterns = Patterns()

    for (offset, line) in lines.enumerated() {
      let number = offset + 1

      if PythonText.hasPrefix(PythonText.lstrip(line), "#") {
        continue
      }

      if let uses = patterns.uses.match(line) {
        let value = PythonText.strip(uses.group("value") ?? "", characters: "'\"")
        let comment = PythonText.strip(uses.group("comment") ?? "")

        if PythonText.hasPrefix(value, "./") {
          // A local action is part of the repository.
        } else if PythonText.hasPrefix(value, "docker://") {
          if patterns.pinnedImage.search(value) == nil {
            found.append("\(relative):\(number): \(value): \(Advice.pinImage)")
          }
        } else if patterns.pinnedAction.match(value) == nil {
          found.append("\(relative):\(number): \(value): pin the action to a full commit SHA, with its version in a comment")
        } else if patterns.versionComment.match(comment) == nil {
          found.append("\(relative):\(number): \(value): add the version the SHA is, as a comment such as # v4.4.0")
        }

        continue
      }

      if let image = patterns.image.match(line) {
        let value = PythonText.strip(image.group("value") ?? "", characters: "'\"")

        // `container:` on its own line has its image on the next, which this checks then.
        if !value.isEmpty, !PythonText.hasPrefix(value, "${{"), patterns.pinnedImage.search(value) == nil {
          found.append("\(relative):\(number): \(value): \(Advice.pinImage)")
        }
      }
    }

    found.append(contentsOf: jobsWithoutTimeouts(in: lines, named: relative))

    return found
  }

  /// Each job, in the workflow's `jobs:` map, that doesn't set `timeout-minutes`.
  func jobsWithoutTimeouts(in lines: [String], named relative: String) -> [String] {
    struct Job {
      let name: String
      let line: Int
      var hasTimeout = false
      var keyIndent: Int?
    }

    let patterns = Patterns()
    var found: [String] = []
    var inJobs = false
    var job: Job?
    var jobIndent: Int?

    func finish() {
      if let job, !job.hasTimeout {
        found.append("\(relative):\(job.line): job \(job.name) has no timeout-minutes")
      }
    }

    for (offset, line) in lines.enumerated() {
      let number = offset + 1

      if PythonText.strip(line).isEmpty || PythonText.hasPrefix(PythonText.lstrip(line), "#") {
        continue
      }

      let indent = PythonText.length(line) - PythonText.length(PythonText.lstrip(line))

      if indent == 0 {
        finish()
        job = nil
        inJobs = PythonText.areEqual(PythonText.rstrip(line), "jobs:")
        continue
      }

      if !inJobs {
        continue
      }

      if jobIndent == nil {
        jobIndent = indent
      }

      if indent == jobIndent {
        finish()
        let name = PythonText.rstrip(PythonText.strip(line), characters: ":")
        job = Job(name: name, line: number)
        continue
      }

      guard var current = job else {
        continue
      }

      // The job's own keys are at the indentation of its first line; a step's keys are deeper.
      if current.keyIndent == nil {
        current.keyIndent = indent
      }

      if indent == current.keyIndent, patterns.timeout.match(line) != nil {
        current.hasTimeout = true
      }

      job = current
    }

    finish()

    return found
  }

  private func workflows(in root: URL) -> URL {
    root.appendingPathComponent(".github").appendingPathComponent("workflows")
  }

  /// The names of the `.yml` and `.yaml` files in the workflows directory, in path order.
  private func workflowNames(in root: URL) throws -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: workflows(in: root).path)) ?? []

    return names
      .filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
      .sorted { PythonText.isOrdered($0, before: $1) }
  }

  private enum Advice {
    static let pinImage = "pin the image by digest, as name:tag@sha256:<digest>"
  }

  private struct Patterns {
    let uses = PythonPattern(
      "^\(s)*(?:-\(s)+)?uses:\(s)*(?<value>[^\(m)#]+)\(s)*(?<comment>#.*)?$"
    )

    let pinnedAction = PythonPattern("^[\(w).\\-]+/[\(w)./\\-]+@[0-9a-f]{40}$")

    // The lookahead stands for `\b`: the match ends on a digit, so a boundary is a non-word next.
    let versionComment = PythonPattern("^#\(s)*v?\(d)+(?:\\.\(d)+)*(?![\(w)])")

    let image = PythonPattern(
      "^\(s)*(?:-\(s)+)?(?:container|image):\(s)*(?<value>[^\(m)#]+)"
    )

    let pinnedImage = PythonPattern("@sha256:[0-9a-f]{64}$")

    let timeout = PythonPattern("^\(s)*timeout-minutes:\(s)*\(PythonPattern.nonSpace)")
  }
}

private let s = PythonPattern.space
private let m = PythonPattern.spaceMembers
private let w = PythonPattern.wordMembers
private let d = PythonPattern.digit
