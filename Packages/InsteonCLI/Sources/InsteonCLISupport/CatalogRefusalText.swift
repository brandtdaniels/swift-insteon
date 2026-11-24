import Foundation
import InsteonCore

/// A published Insteon device catalog that `insteon catalog update` refused, because it
/// relaxes safeguards the bundled copy keeps.
public struct CatalogRefusal: Hashable, Sendable {

  /// The published catalog's version, or `nil` if the check didn't read it.
  public var published: DeviceCatalogVersion?

  /// The bundled copy's version, whose safeguards the published catalog is compared with.
  public var bundled: DeviceCatalogVersion

  /// The version of the copy in use, which stays.
  public var current: DeviceCatalogVersion

  /// Each safeguard the published catalog relaxes.
  public var weakenings: [GuardWeakening]

  /// Creates a refusal.
  ///
  /// - Parameters:
  ///   - published: The published catalog's version, or `nil` if it isn't known.
  ///   - bundled: The bundled copy's version.
  ///   - current: The version of the copy in use.
  ///   - weakenings: Each safeguard the published catalog relaxes.
  public init(published: DeviceCatalogVersion?, bundled: DeviceCatalogVersion, current: DeviceCatalogVersion, weakenings: [GuardWeakening]) {

    self.published = published
    self.bundled = bundled
    self.current = current
    self.weakenings = weakenings

  }

}

/// The kinds of difference a refusal lists, in the order they're shown.
public enum CatalogDifferenceKind: String, CaseIterable, Hashable, Sendable {

  /// A command whose effect is looser in the published catalog.
  case effectChanged

  /// A command the published catalog marks idempotent that the bundled copy doesn't.
  case idempotencyChanged

  /// A command the bundled copy describes that the published catalog leaves out.
  case droppedEntry

  /// A serial command the bundled copy leaves undescribed that the published catalog describes.
  case serialNowDescribed

  /// Any other relaxed safeguard, such as operating flag bits.
  case other

  /// The kind's name as a heading.
  public var title: String {

    switch self {
    case .effectChanged: "Effect changes"
    case .idempotencyChanged: "Idempotency changes"
    case .droppedEntry: "Dropped entries"
    case .serialNowDescribed: "Undescribed serial commands now described"
    case .other: "Other guard changes"
    }

  }

}

/// The differences of one kind.
public struct CatalogDifferenceGroup: Hashable, Sendable {

  /// The kind of every difference in the group.
  public var kind: CatalogDifferenceKind

  /// The differences, ordered by device, then detail, then firmware version.
  public var differences: [GuardWeakening]

  /// The kind's heading.
  public var title: String { kind.title }

  /// How many products the differences touch: the distinct category and subcategory pairs.
  public var productCount: Int {

    Set(differences.map { (weakening: GuardWeakening) -> [UInt8] in [weakening.category.rawValue, weakening.subcategory.rawValue] }).count

  }

  /// The group's heading with its counts, such as `Effect changes: 2 differences across 2 products`.
  public var heading: String {

    "\(title): \(CatalogRefusalText.count(differences.count, "difference")) across \(CatalogRefusalText.count(productCount, "product"))"

  }

}

/// The text `insteon catalog update` prints when the published catalog is refused.
public enum CatalogRefusalText {

  /// The longest line the text makes.
  public static let width: Int = 100

  /// How many differences of a kind the summary shows.
  public static let examplesPerKind: Int = 3

  /// The differences grouped by kind, in the order the kinds are shown, leaving out a kind with
  /// none.
  ///
  /// - Parameter weakenings: The relaxed safeguards.
  /// - Returns: The groups.
  public static func groups(_ weakenings: [GuardWeakening]) -> [CatalogDifferenceGroup] {

    let sorted: [GuardWeakening] = weakenings.sorted { (left: GuardWeakening, right: GuardWeakening) -> Bool in

      let leftKey: (UInt8, UInt8, String, Int) = (left.category.rawValue, left.subcategory.rawValue, left.detail, left.firmwareVersion.map { Int($0.rawValue) } ?? -1)
      let rightKey: (UInt8, UInt8, String, Int) = (right.category.rawValue, right.subcategory.rawValue, right.detail, right.firmwareVersion.map { Int($0.rawValue) } ?? -1)

      return leftKey < rightKey

    }

    return CatalogDifferenceKind.allCases.compactMap { (candidate: CatalogDifferenceKind) -> CatalogDifferenceGroup? in

      let members: [GuardWeakening] = sorted.filter { (weakening: GuardWeakening) -> Bool in differenceKind(of: weakening) == candidate }

      return members.isEmpty ? nil : CatalogDifferenceGroup(kind: candidate, differences: members)

    }

  }

  /// The kind a relaxed safeguard belongs to.
  static func differenceKind(of weakening: GuardWeakening) -> CatalogDifferenceKind {

    switch weakening.kind {
    case .idempotent:
      return .idempotencyChanged
    case .effect:
      if weakening.detail.hasSuffix(" to undescribed") {

        return .droppedEntry

      }

      return weakening.detail.contains(" undescribed to ") ? .serialNowDescribed : .effectChanged
    default:
      return .other
    }

  }

  /// The sentence that says what happened and that the copy in use stays, wrapped to
  /// ``width``.
  ///
  /// - Parameter refusal: The refusal.
  /// - Returns: The lines.
  public static func opening(_ refusal: CatalogRefusal) -> [String] {

    let published: String = refusal.published.map { ", \($0)," } ?? ""

    return wrap("The published Insteon device catalog\(published) relaxes safeguards that the bundled copy, \(refusal.bundled), keeps, so it isn't used.")

  }

  /// The sentence that says which copy stays, wrapped to ``width``.
  ///
  /// - Parameter refusal: The refusal.
  /// - Returns: The lines.
  public static func staying(_ refusal: CatalogRefusal) -> [String] {

    if refusal.current == refusal.bundled {

      return wrap("The bundled copy, \(refusal.bundled), stays until a new version of this tool ships a refreshed bundle.")

    }

    return wrap(
      "The current copy, \(refusal.current), stays, and the bundled copy, \(refusal.bundled), stays until a new version of this tool ships a refreshed bundle."
    )

  }

  /// The hint for the complete list.
  public static let explainHint: String = "Run 'insteon catalog update --explain' to see every difference, one per line."

  /// What `insteon catalog update` prints on standard error for a refusal: what happened, the
  /// differences by kind with a count and the first few examples, which copy stays, and how to
  /// see everything. No line is longer than ``width``.
  ///
  /// - Parameter refusal: The refusal.
  /// - Returns: The lines.
  public static func summary(_ refusal: CatalogRefusal) -> [String] {

    let groups: [CatalogDifferenceGroup] = groups(refusal.weakenings)
    let products: Int = Set(refusal.weakenings.map { (weakening: GuardWeakening) -> [UInt8] in [weakening.category.rawValue, weakening.subcategory.rawValue] }).count
    var lines: [String] = opening(refusal)

    lines.append("")
    lines += wrap("\(count(refusal.weakenings.count, "difference")) in \(count(groups.count, "kind")), across \(count(products, "product")):")
    lines.append("")

    for group in groups {

      lines += wrap(group.heading)

      for weakening in group.differences.prefix(examplesPerKind) {

        lines += wrap(text(of: weakening), lead: "    \(location(of: weakening))  ", hanging: "      ")

      }

      if group.differences.count > examplesPerKind {

        lines.append("    and \(group.differences.count - examplesPerKind) more")

      }

    }

    lines.append("")
    lines += staying(refusal)
    lines.append(explainHint)

    return lines

  }

  /// What `insteon catalog update --explain` prints on standard output for a refusal: every
  /// difference on its own line, grouped by kind, each group in order of device, detail and
  /// firmware version.
  ///
  /// - Parameter refusal: The refusal.
  /// - Returns: The lines.
  public static func explanation(_ refusal: CatalogRefusal) -> [String] {

    var lines: [String] = []

    for group in groups(refusal.weakenings) {

      if !lines.isEmpty {

        lines.append("")

      }

      lines.append(group.heading)
      lines += group.differences.map { (weakening: GuardWeakening) -> String in "\(location(of: weakening)) \(text(of: weakening))" }

    }

    return lines

  }

  /// The refusal's differences as JSON, for `insteon catalog update --explain --json`.
  ///
  /// - Parameter refusal: The refusal.
  /// - Returns: The JSON text.
  /// - Throws: `EncodingError` if it can't be encoded.
  public static func explanationJSON(_ refusal: CatalogRefusal) throws -> String {

    try json(status: "refused", refusal: refusal)

  }

  /// The JSON for an update that wasn't refused: its status and no differences.
  ///
  /// - Parameter status: `updated`, `current` or `kept`.
  /// - Returns: The JSON text.
  /// - Throws: `EncodingError` if it can't be encoded.
  public static func noDifferencesJSON(status: String) throws -> String {

    try json(status: status, refusal: nil)

  }

  /// A difference's detail, led by its kind where the group doesn't say it, as for other guard
  /// changes.
  static func text(of weakening: GuardWeakening) -> String {

    differenceKind(of: weakening) == .other ? "\(weakening.kind.rawValue) \(weakening.detail)" : weakening.detail

  }

  /// `0x01/0x21`, with the firmware version when the difference is for one.
  static func location(of weakening: GuardWeakening) -> String {

    let device: String = "\(weakening.category)/\(weakening.subcategory)"

    return weakening.firmwareVersion.map { "\(device) (firmware \($0))" } ?? device

  }

  /// A count with its noun, such as `1 product` or `2 products`.
  static func count(_ number: Int, _ noun: String) -> String {

    "\(number) \(noun)\(number == 1 ? "" : "s")"

  }

  /// Breaks `text` at spaces so no line is longer than ``width``, unless one word is. The first
  /// line starts with `lead`, and the rest with `hanging`.
  static func wrap(_ text: String, lead: String = "", hanging: String = "") -> [String] {

    var lines: [String] = []
    var line: String = lead
    var hasWord: Bool = false

    for word in text.split(separator: " ", omittingEmptySubsequences: true) {

      if !hasWord {

        line += word
        hasWord = true

      } else if line.count + 1 + word.count > width {

        lines.append(line)
        line = hanging + word

      } else {

        line += " " + word

      }

    }

    lines.append(line)

    return lines

  }

  private struct Report: Encodable {

    var status: String
    var published: String?
    var bundled: String?
    var current: String?
    var groups: [Group]

  }

  private struct Group: Encodable {

    var kind: String
    var title: String
    var count: Int
    var products: Int
    var differences: [Difference]

  }

  private struct Difference: Encodable {

    var category: String
    var subcategory: String
    var firmwareVersion: String?
    var kind: String
    var detail: String

  }

  private static func json(status: String, refusal: CatalogRefusal?) throws -> String {

    let groups: [Group] = refusal.map { (refusal: CatalogRefusal) -> [Group] in

      Self.groups(refusal.weakenings).map { (group: CatalogDifferenceGroup) -> Group in

        Group(
          kind: group.kind.rawValue,
          title: group.title,
          count: group.differences.count,
          products: group.productCount,
          differences: group.differences.map { (weakening: GuardWeakening) -> Difference in

            Difference(
              category: "\(weakening.category)",
              subcategory: "\(weakening.subcategory)",
              firmwareVersion: weakening.firmwareVersion.map { "\($0)" },
              kind: weakening.kind.rawValue,
              detail: weakening.detail
            )

          }
        )

      }

    } ?? []
    let report = Report(
      status: status,
      published: refusal?.published.map { "\($0)" },
      bundled: refusal.map { "\($0.bundled)" },
      current: refusal.map { "\($0.current)" },
      groups: groups
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    return String(decoding: try encoder.encode(report), as: UTF8.self)

  }

}
