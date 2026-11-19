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

/// Mutants from several generators, chosen by weight.
public struct WeightedMutations: MutantGenerating {
  private let generators: [(generator: MutantGenerating, weight: Int)]

  public init(_ generators: [(MutantGenerating, Int)]) {
    self.generators = generators.map { (generator: $0.0, weight: $0.1) }
  }

  public func makeMutant(in tree: MutableTree, using generator: inout SeededGenerator) throws -> Mutant {
    var roll = Int.random(in: 0..<generators.reduce(0) { $0 + $1.weight }, using: &generator)
    for entry in generators {
      if roll < entry.weight {
        return try entry.generator.makeMutant(in: tree, using: &generator)
      }
      roll -= entry.weight
    }
    return try generators[0].generator.makeMutant(in: tree, using: &generator)
  }
}
