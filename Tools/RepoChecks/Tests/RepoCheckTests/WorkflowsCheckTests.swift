import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

private let sha = "11d5960a326750d5838078e36cf38b85af677262"

private let digest = "sha256:" + String(repeating: "0123456789abcdef", count: 4)

private let pinned = """
  name: CI
  on: [push]
  jobs:
    lint:
      name: Lint
      runs-on: ubuntu-latest
      timeout-minutes: 10
      steps:
        - uses: actions/checkout@\(sha) # v4.4.0
        - uses: ./.github/actions/local
        - name: Run
          run: echo "uses: actions/checkout@v4"
    linux:
      runs-on: ubuntu-latest
      container: swift:6.3.3@\(digest)
      timeout-minutes: 30
      services:
        cache:
          image: redis:7@\(digest)
      steps:
        - uses: docker://alpine:3.20@\(digest)

  """

/// A repository root holding workflows, in a directory that goes away with it.
private struct Repository {
  let directory = try! ScratchDirectory()

  var root: URL { directory.url }

  func write(_ workflow: String, as name: String = "ci.yml") throws {
    try directory.write(workflow, to: ".github/workflows/\(name)")
  }

  func problems(_ workflow: String) throws -> [String] {
    try write(workflow)
    return try WorkflowsCheck().problems(in: root)
  }
}

@Suite("check-workflows")
struct WorkflowsCheckTests {
  // test_accepts_pinned_actions_and_images_and_jobs_with_limits
  @Test("accepts pinned actions and images and jobs with limits")
  func acceptsPinnedWorkflow() throws {
    #expect(try Repository().problems(pinned) == [])
  }

  // test_refuses_an_action_by_tag_or_short_sha
  @Test("refuses an action by tag or short SHA")
  func refusesTagOrShortSHA() throws {
    var workflow = pinned.replacing("actions/checkout@\(sha) # v4.4.0", with: "actions/checkout@v4")
    workflow = workflow.replacing("./.github/actions/local", with: "actions/cache@11d5960")

    let found = try Repository().problems(workflow)

    #expect(found.count == 2)
    #expect(found.first?.contains("ci.yml:9: actions/checkout@v4: pin the action") == true)
    #expect(found.last?.contains("ci.yml:10: actions/cache@11d5960: pin the action") == true)
  }

  // test_asks_for_the_version_of_a_pinned_action
  @Test("asks for the version of a pinned action")
  func asksForVersion() throws {
    let found = try Repository().problems(pinned.replacing(" # v4.4.0", with: ""))

    #expect(found.count == 1)
    #expect(found.first?.contains("add the version the SHA is") == true)
  }

  // test_refuses_an_image_by_tag
  @Test("refuses an image by tag")
  func refusesImageByTag() throws {
    var workflow = pinned.replacing("swift:6.3.3@\(digest)", with: "swift:6.3.3")
    workflow = workflow.replacing("redis:7@\(digest)", with: "redis:7")
    workflow = workflow.replacing("alpine:3.20@\(digest)", with: "alpine:3.20")

    let found = try Repository().problems(workflow)

    #expect(found.map { $0.components(separatedBy: ": ")[1] } == ["swift:6.3.3", "redis:7", "docker://alpine:3.20"])
  }

  // test_refuses_a_job_without_a_time_limit
  @Test("refuses a job without a time limit")
  func refusesJobWithoutLimit() throws {
    let found = try Repository().problems(pinned.replacing("    timeout-minutes: 10\n", with: ""))

    #expect(found == [".github/workflows/ci.yml:4: job lint has no timeout-minutes"])
  }

  // test_doesnt_count_a_steps_time_limit_for_its_job
  @Test("doesn't count a step's time limit for its job")
  func doesNotCountStepLimit() throws {
    let workflow = pinned
      .replacing("    timeout-minutes: 10\n", with: "")
      .replacing("      run: echo", with: "      timeout-minutes: 5\n      run: echo")

    let found = try Repository().problems(workflow)

    #expect(found == [".github/workflows/ci.yml:4: job lint has no timeout-minutes"])
  }

  // test_exits_with_status_1_on_a_problem_and_0_without
  @Test("ends with status 1 on a problem and 0 without")
  func statusFollowsFindings() throws {
    let repository = Repository()

    try repository.write(pinned.replacing(" # v4.4.0", with: ""))
    #expect(try WorkflowsCheck().run(in: repository.root, console: RecordingConsole()) == .failed)

    try repository.write(pinned)
    #expect(try WorkflowsCheck().run(in: repository.root, console: RecordingConsole()) == .passed)
    #expect(CheckStatus.failed.rawValue == 1)
    #expect(CheckStatus.passed.rawValue == 0)
  }
}

@Suite("check-workflows report")
struct WorkflowsCheckReportTests {
  @Test("prints each problem on a line of its own")
  func printsEachProblem() throws {
    let repository = Repository()
    try repository.write(pinned.replacing(" # v4.4.0", with: "").replacing("    timeout-minutes: 10\n", with: ""))
    let console = RecordingConsole()

    _ = try WorkflowsCheck().run(in: repository.root, console: console)

    #expect(
      console.output == """
        .github/workflows/ci.yml:8: actions/checkout@\(sha): add the version the SHA is, as a comment such as # v4.4.0
        .github/workflows/ci.yml:4: job lint has no timeout-minutes

        """
    )
    #expect(console.errorLines.isEmpty)
  }

  @Test("says everything is pinned and limited when it is")
  func printsSuccess() throws {
    let repository = Repository()
    try repository.write(pinned)
    let console = RecordingConsole()

    _ = try WorkflowsCheck().run(in: repository.root, console: console)

    #expect(console.lines == ["Every action and image is pinned, and every job has a time limit."])
  }

  @Test("words the three advice texts and the image advice as the script did")
  func wordsAdvice() throws {
    let workflow = """
      jobs:
        a:
          timeout-minutes: 1
          container: x:1
          steps:
            - uses: actions/checkout@v4
            - uses: actions/checkout@\(sha)
            - uses: docker://y:2

      """

    let found = try Repository().problems(workflow)

    #expect(
      found == [
        ".github/workflows/ci.yml:4: x:1: pin the image by digest, as name:tag@sha256:<digest>",
        ".github/workflows/ci.yml:6: actions/checkout@v4: pin the action to a full commit SHA, with its version in a comment",
        ".github/workflows/ci.yml:7: actions/checkout@\(sha): add the version the SHA is, as a comment such as # v4.4.0",
        ".github/workflows/ci.yml:8: docker://y:2: pin the image by digest, as name:tag@sha256:<digest>"
      ]
    )
  }
}

@Suite("check-workflows reading")
struct WorkflowsCheckReadingTests {
  @Test("reads .yml and .yaml files in path order and nothing else")
  func readsYmlAndYaml() throws {
    let repository = Repository()
    let bad = pinned.replacing(" # v4.4.0", with: "")
    try repository.write(bad, as: "b.yaml")
    try repository.write(bad, as: "a.yml")
    try repository.write(bad, as: "c.txt")
    try repository.write(bad, as: "d.YML")

    let found = try WorkflowsCheck().problems(in: repository.root)

    #expect(found.map { $0.components(separatedBy: ":")[0] } == [".github/workflows/a.yml", ".github/workflows/b.yaml"])
  }

  @Test("finds nothing to report when there is no workflows directory")
  func missingDirectory() throws {
    let directory = try ScratchDirectory()

    #expect(try WorkflowsCheck().problems(in: directory.url) == [])
  }

  @Test("numbers lines the same under CRLF and lone CR endings")
  func normalizesNewlines() throws {
    let bad = pinned.replacing(" # v4.4.0", with: "")

    #expect(try Repository().problems(bad.replacing("\n", with: "\r\n")).first?.contains("ci.yml:9:") == true)
    #expect(try Repository().problems(bad.replacing("\n", with: "\r")).first?.contains("ci.yml:9:") == true)
  }

  @Test("skips comment lines, including a commented uses")
  func skipsComments() throws {
    let workflow = pinned.replacing(
      "      steps:\n",
      with: "      steps:\n        # - uses: actions/checkout@v4\n        # container: x:1\n"
    )

    #expect(try Repository().problems(workflow) == [])
  }

  @Test("strips quotes around a value before checking it")
  func stripsQuotes() throws {
    let workflow = pinned.replacing("actions/checkout@\(sha) # v4.4.0", with: "\"actions/checkout@v4\" # v4")

    #expect(try Repository().problems(workflow).first?.contains("9: actions/checkout@v4: pin the action") == true)
  }

  @Test("takes an expression as an image it can't check")
  func skipsExpressionImage() throws {
    let workflow = pinned.replacing("container: swift:6.3.3@\(digest)", with: "container: ${{ matrix.image }}")

    #expect(try Repository().problems(workflow) == [])
  }

  @Test("checks the image on the line after a bare container key when that line is an image")
  func bareContainerKey() throws {
    let workflow = pinned.replacing(
      "container: swift:6.3.3@\(digest)",
      with: "container:\n      image: swift:6.3.3"
    )

    let found = try Repository().problems(workflow)

    #expect(found == [".github/workflows/ci.yml:16: swift:6.3.3: pin the image by digest, as name:tag@sha256:<digest>"])
  }

  @Test("takes a version comment that Python's pattern takes")
  func versionComments() throws {
    for comment in ["# v4", "#4.4.0", "#   v1.2.3 (latest)", "# v1.2.", "# v1.2x"] {
      let workflow = pinned.replacing("# v4.4.0", with: comment)
      #expect(try Repository().problems(workflow) == [], "\(comment)")
    }
    for comment in ["# latest", "# vx", "#", "# V4"] {
      let workflow = pinned.replacing("# v4.4.0", with: comment)
      #expect(try Repository().problems(workflow).count == 1, "\(comment)")
    }
  }

  @Test("reads a line break character inside a comment as part of the comment")
  func unusualLineEnds() throws {
    let workflow = pinned.replacing("# v4.4.0", with: "# v4.4.0 \u{2028}\u{85}\u{B} end")

    #expect(try Repository().problems(workflow) == [])
  }

  @Test("counts indentation in code points, with a tab as one")
  func tabIndentation() throws {
    let workflow = "jobs:\n\ta:\n\t\ttimeout-minutes: 3\n\tb:\n\t\truns-on: x\n"

    #expect(try Repository().problems(workflow) == [".github/workflows/ci.yml:4: job b has no timeout-minutes"])
  }

  @Test("refuses a workflow that isn't UTF-8")
  func refusesInvalidUTF8() throws {
    let repository = Repository()
    try repository.directory.write(Data([0xFF, 0xFE]), to: ".github/workflows/ci.yml")

    #expect(throws: TextFileError.self) {
      try WorkflowsCheck().problems(in: repository.root)
    }
  }

  @Test("passes on this repository's own workflows")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    #expect(try WorkflowsCheck().problems(in: root) == [])
  }
}
