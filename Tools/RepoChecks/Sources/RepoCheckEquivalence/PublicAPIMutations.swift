import Foundation

/// Mutants aimed at `check-public-api`: declarations in the forms its reader handles and
/// mishandles, access changes to the real sources, and edits of the list.
public enum PublicAPIMutations {
  static let listPath = "Scripts/insteoncore-public-api.txt"

  static let snippets = [
    "public struct Added {}", "public struct Added { public var a: Int; public var b: Int; var c: Int }", "struct Hidden { public var x: Int }",
    "public enum E { case a, b, c }", "public enum E { case a = 1, b = 2 }", "public enum E {\n  case sent(Data, to: Address), heard(_ level: Int)\n  case idle\n  case `default`(x: Int)\n  case empty()\n}",
    "public enum E: Int {\n  case a,\n    b\n}", "enum Internal { case one }", "public protocol P {\n  associatedtype Item\n  func f(_ x: Int) async throws\n  var v: Bool { get }\n  init(x: Int)\n  subscript(i: Int) -> Int { get }\n}",
    "protocol Hidden { func g() }", "public extension Store {\n  func load() -> Data? { nil }\n  static var shared: Store { Store() }\n  internal func helper() {}\n  private func hidden() {}\n  fileprivate var cache: Int { 0 }\n  package func packaged() {}\n}",
    "extension Store {\n  func notPublic() {}\n  public func stated() {}\n}", "public func f(_ a: Int, b: String = \"x\", c d: [Int: Int], e: @Sendable (Int) async throws -> Bool) {}",
    "public func g<T: Sendable>(_ value: T) where T: Equatable {}", "public func `back`(`tick` x: Int) {}", "public func ==(lhs: A, rhs: A) -> Bool { true }",
    "public static func + (lhs: A, rhs: A) -> A { lhs }", "public init?(_ text: String, strict: Bool = false) { nil }", "public init!(x: Int) {}",
    "public init<T>(_ t: T) {}", "public subscript(index: Int, other: Int) -> UInt8 { 0 }", "public var a: Int { get set }", "public private(set) var count: Int = 0",
    "public internal(set) var name: String", "public fileprivate(set) var v: Int", "open class Open { open func f() {} public class func g() {} }",
    "public final class Box { public class func make() -> Box { Box() } }", "public actor Registry { public nonisolated let id: Int = 0 }",
    "@_spi(Raw)\npublic func raw(_ b: [UInt8]) {}", "@_spi(Raw) public struct R {}", "@_spi(Raw)\npublic struct R2 {\n  public func inner() {}\n}", "@discardableResult\npublic func d() -> Int { 1 }",
    "@available(macOS 13, *)\n@MainActor\npublic func m() {}", "public typealias T = Int", "public typealias `T2` = Int", "public struct Outer {\n  public struct Inner {\n    public var deep: Int\n  }\n}",
    "public struct S {\n  func body() {\n    struct Local { public var x: Int }\n    let c = { case }\n  }\n}", "public struct G<T> where T: Hashable { public func h() {} }", "public\nfunc split() {}",
    "public func a() {}; public func b() {}", "public var multi: Int, other: Int", "public let (x, y) = (1, 2)", "class func notDecl() {}", "public class func modifierClass() {}",
    "public indirect enum Tree { case leaf, node(Tree, Tree) }", "public struct Wrapper {\n  @Published public var p: Int\n  public lazy var l: Int = 0\n  public weak var w: AnyObject?\n}",
    "public func closure(_ f: (Int) -> Void, g: () -> Int) {}", "public func generic<A, B>(_ a: A, _ b: B) -> (A, B) { (a, b) }", "public consuming func eat() {}", "public func inoutParam(_ x: inout Int, isolated y: Actor) {}"
  ]

  static let sourceOperators: [TextOperator] = [
    CodeMutations.insertSnippet(from: snippets),
    CodeMutations.appendSnippet(from: snippets),
    TextOperator("dropPublic") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("public ") }),
        let changed = lines[index].replacingFirst(of: "public ", with: "")
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("addPublic") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("func ") || $0.contains("var ") || $0.contains("struct ") || $0.contains("case ") }) else { return false }
      let spaces = lines[index].leadingSpaces
      lines[index] = String(repeating: " ", count: spaces) + ["public ", "open ", "package ", "private "].randomElement(using: &generator)! + lines[index].dropFirst(spaces)
      return true
    },
    TextOperator("setterAccess") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("public var ") }),
        let changed = lines[index].replacingFirst(of: "public var ", with: ["public private(set) var ", "public internal(set) var ", "private(set) var ", "public(set) var "].randomElement(using: &generator)!)
      else { return false }
      lines[index] = changed
      return true
    },
    TextOperator("spiAbove") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains("public ") }) else { return false }
      lines.insert(String(repeating: " ", count: lines[index].leadingSpaces) + ["@_spi(Raw)", "@_spi(Other) @MainActor", "@inlinable", ""].randomElement(using: &generator)!, at: index)
      return true
    },
    TextOperator("joinLines") { lines, generator in
      guard lines.count > 1 else { return false }
      let index = Int.random(in: 0..<(lines.count - 1), using: &generator)
      lines[index] += " " + lines[index + 1].drop { $0 == " " }
      lines.remove(at: index + 1)
      return true
    },
    TextOperator("splitLine") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.contains(" func ") || $0.contains(" var ") || $0.contains(" case ") }),
        let range = lines[index].range(of: " ", options: .backwards)
      else { return false }
      lines.replaceSubrange(index...index, with: [String(lines[index][..<range.lowerBound]), String(lines[index][range.upperBound...])])
      return true
    },
    TextOperator("braceMove") { lines, generator in
      guard let index = lines.randomIndex(using: &generator, where: { $0.hasSuffix(" {") }) else { return false }
      lines[index] = String(lines[index].dropLast(2))
      lines.insert("{", at: index + 1)
      return true
    }
  ] + CommonOperators.all

  static let listOperators = CodeMutations.allowListOperators(columns: 1, samples: [["struct Added"], ["func Nope.gone()"], ["case E.a"], ["@_spi(Raw) func raw(_:)"]])
    + CommonOperators.all

  public static func generator(tree: MutableTree) throws -> MutantGenerating {
    let sources = try tree.filesWithSuffixes([".swift"]).filter { $0.hasPrefix("Packages/InsteonCore/Sources/InsteonCore/") }
    return WeightedMutations([
      (try TextFileMutations(tree: tree, paths: sources, operators: sourceOperators), 8),
      (try TextFileMutations(tree: tree, paths: [listPath], operators: listOperators), 2)
    ])
  }
}
