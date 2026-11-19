import Foundation

/// Mutants aimed at `check-time-limits`: tests with and without limits, suites, extensions,
/// effects and return types, and the comments and strings that must hide them.
public enum TimeLimitsMutations {
  static let snippets = [
    "@Test func waits() async {}", "@Test(.timeLimit(.minutes(1))) func waits() async {}",
    "@Test(\"Named\", .timeLimit(.minutes(1))) func named() async {}", "@Test(\n  \"Over lines\",\n  .timeLimit(.minutes(1))\n)\nfunc overLines() async throws {}",
    "@Test func sync() throws {}", "@Test func returnsAClosure() -> () async -> Void { {} }",
    "@Test func generic<T: Sendable>(_ value: T = 1) async throws(SomeError) where T: Equatable {}",
    "@Test func `with spaces`() async {}", "@Test(arguments: [1, 2]) func each(_ x: Int) async {}",
    "@Test @MainActor func main() async {}", "@Test public func visible() async {}", "@Test private(set) func hidden() async {}",
    "@Test final func finalOne() async {}", "@Testing func nope() async {}", "@Test\nfunc below() async {}", "@Test()\nfunc empty() async {}",
    "@Test func noBody() async", "@Test func a() async -> Int { 1 }", "@Test func `` () async {}", "@Test func \u{E9}tude() async {}",
    "@Test func x(timeLimit: Int) async {}", "@Test(.tags(.x)) func tagged() async {}", "@Test(\"timeLimit(\") func quoted() async {}",
    "@Suite(.timeLimit(.minutes(1)))\nstruct LimitedSuite {\n  @Test func inside() async {}\n}",
    "@Suite(.serialized)\nstruct PlainSuite {\n  @Test func inside() async {}\n}",
    "@Suite(.timeLimit(.minutes(1)))\nstruct Suite2 {}\nextension Suite2 {\n  @Test func later() async {}\n}",
    "extension Unknown {\n  @Test func lost() async {}\n}", "@Suite(.timeLimit(.minutes(1))) @MainActor final class C {\n  struct N {\n    @Test func deep() async {}\n  }\n}",
    "public enum E {\n  @Test func inEnum() async {}\n}", "actor A {\n  @Test func inActor() async {}\n}",
    "let x = 1\nstruct After {\n  @Test func afterLet() async {}\n}", "@Suite\nstruct NoArgs {\n  @Test func z() async {}\n}",
    "struct Outer.Inner {\n  @Test func dotted() async {}\n}", "class Foo {}\n@Suite(.timeLimit(.minutes(1)))\nextension Foo {\n  @Test func ext() async {}\n}"
  ]

  public static let operators: [TextOperator] = [
    CodeMutations.insertSnippet(from: snippets),
    CodeMutations.appendSnippet(from: snippets),
    TextOperator("removeTimeLimit") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("timeLimit(") }),
        let changed = lines[index].replacingFirst(of: "\\.timeLimit\\(\\.minutes\\(\\d+\\)\\)", with: ["", ".serialized", ".tags(.x)"].randomElement(using: &generator)!)
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("deleteSuite") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("@Suite") }) else { return false }
      lines.remove(at: index)
      return true
    },
    TextOperator("makeAsync") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("func ") && $0.contains(") ") && !$0.contains("async") }),
        let changed = lines[index].replacingFirst(of: "\\) (?=[{t])", with: [") async ", ") async throws ", ") throws -> async "].randomElement(using: &generator)!)
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("addTestAttribute") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("func ") }) else { return false }
      let indent = String(repeating: " ", count: lines[index].leadingSpaces)
      lines.insert(indent + ["@Test", "@Test(.timeLimit(.minutes(1)))", "@Test(\"x\")", "@Test @MainActor"].randomElement(using: &generator)!, at: index)
      return true
    },
    TextOperator("renameType") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("struct ") || $0.contains("extension ") || $0.contains("class ") }),
        let changed = lines[index].replacingFirst(of: "(struct|extension|class|enum) \\w+", with: "$1 Renamed\(Int.random(in: 0..<3, using: &generator))")
      else { return false }
      lines[index] = changed
      return true
    }
  ] + CommonOperators.all
}
