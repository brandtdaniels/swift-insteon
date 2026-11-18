import Foundation

/// A change to the tree that a check must treat the same in Python and in Swift.
public struct Mutant: Equatable, Sendable {
  /// What it does, in words, for the report.
  public var description: String

  public var edits: [FileEdit]

  public init(description: String, edits: [FileEdit]) {
    self.description = description
    self.edits = edits
  }
}

/// A source of mutants for one check.
public protocol MutantGenerating {
  /// A mutant of the tree, made from the generator's numbers alone.
  func makeMutant(in tree: MutableTree, using generator: inout SeededGenerator) throws -> Mutant
}
