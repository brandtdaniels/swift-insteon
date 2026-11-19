import Foundation

/// Mutants aimed at `check-concurrency`: the code its rules look for, and its allow-list.
public enum ConcurrencyMutations {
  static let snippets = [
    "Task { await work() }", "Task(priority: .low) { }", "Task<Void, Never> { }", "Task<Void, Never>() { }", "Task.detached { }",
    "Task.init { }", "Task {", "let t = Task { () async -> Void in", "Task<[String: Int], Error> { }", "Task < x { }",
    "Task\n{", "@unchecked Sendable", "@unchecked   Sendable", "final class A: @unchecked Sendable {}", "@unchecked Sendable2",
    "Task.sleep(for: .seconds(1))", "Task.sleep(nanoseconds: 1)", "Task.sleepy", "ContinuousClock()", "SuspendingClock()",
    "let clock = ContinuousClock()", "var c: any Clock<Duration> = ContinuousClock()", "init(clock: any Clock<Duration> = ContinuousClock()) {}",
    "func f(clock: some Clock<Duration> = SuspendingClock(), x: Int) {}", "func f(a: Int = 1, clock: C = ContinuousClock()) {}",
    "let x: C = ContinuousClock()", "run(clock: ContinuousClock())", "ContinuousClock ()", "ContinuousClock(\u{301})",
    "x = ContinuousClock() + SuspendingClock()", "clock: Clock = ContinuousClock(), other: Clock = ContinuousClock()",
    "static let c: C = ContinuousClock()", "var v = f(clock: C = ContinuousClock())", "Task.detached", "Task .detached",
    "MyTask { }", "Task2 { }", "let task: Task<Void, Never>? = nil", "group.addTask { }"
  ]

  public static let sourceOperators: [TextOperator] = [
    CodeMutations.insertSnippet(from: snippets),
    CodeMutations.appendSnippet(from: snippets)
  ] + CommonOperators.all

  public static let allowListOperators = CodeMutations.allowListOperators(
    columns: 4,
    samples: [
      ["InsteonCore/Sources/InsteonCore/X.swift", "unstructured-task", "Task { }", "A reason."],
      ["InsteonCLI/Sources/InsteonCLISupport/LineReader.swift", "unchecked-sendable", "public final class LineReader: @unchecked Sendable {", "Locked."],
      ["Nope/Sources/N.swift", "real-clock", "let c = ContinuousClock()", "x"]
    ]
  ) + CommonOperators.all
}
