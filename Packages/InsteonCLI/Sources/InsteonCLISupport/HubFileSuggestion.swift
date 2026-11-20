/// The file name and command `insteon discover` offers for a Hub it lists, so the Hub can be
/// used by name.
///
/// A name is the Hub's type, `hub` or `hubpro`, and a short suffix: the last four hexadecimal
/// digits of its Insteon ID, else the last number of its address. Names in one list are
/// unique, and each is a valid ``HubName``.
///
/// ```swift
/// let source = HubFileSuggestion.Source(isHubPro: false, insteonID: "1A.2B.3C", host: "192.168.1.20", port: 25105)
/// HubFileSuggestion.suggestions(for: [source]).first?.command
/// // "insteon --hub hub-2b3c info"
/// ```
public struct HubFileSuggestion: Hashable, Sendable {

  /// A Hub `insteon discover` found.
  public struct Source: Hashable, Sendable {

    /// Whether the Hub is a Hub Pro.
    public var isHubPro: Bool

    /// The Hub's Insteon ID, such as `1A.2B.3C`, if it's known.
    public var insteonID: String?

    /// The Hub's host.
    public var host: String

    /// The port of the Hub's interface.
    public var port: Int

    /// Creates a found Hub.
    ///
    /// - Parameters:
    ///   - isHubPro: Whether the Hub is a Hub Pro.
    ///   - insteonID: The Hub's Insteon ID, if known.
    ///   - host: The Hub's host.
    ///   - port: The port of the Hub's interface.
    public init(isHubPro: Bool, insteonID: String?, host: String, port: Int) {

      self.isHubPro = isHubPro
      self.insteonID = insteonID
      self.host = host
      self.port = port

    }

  }

  /// The name to give `--hub`.
  public var name: String

  /// The name of the file to save the Hub's settings in: the name and `.env`.
  public var fileName: String {

    name + HubFiles.fileExtension

  }

  /// The command that uses the Hub by name.
  public var command: String {

    "insteon --hub \(name) info"

  }

  /// What to do with the files, as one line for a person.
  public static let note = "To use a Hub by name, save its INSTEON_HUB_USERNAME, INSTEON_HUB_PASSWORD and INSTEON_HUB_HOST in the file shown, readable only by you with chmod 600."

  /// A suggestion for each Hub, in order.
  ///
  /// - Parameter hubs: The Hubs found.
  /// - Returns: A suggestion for each, with names that differ from each other.
  public static func suggestions(for hubs: [Source]) -> [HubFileSuggestion] {

    var taken: Set<String> = []

    return hubs.map { (hub: Source) -> HubFileSuggestion in

      let base = baseName(for: hub)
      var name = base
      var number = 2

      while taken.contains(name) {

        name = base + "-" + String(number)
        number += 1

      }

      taken.insert(name)

      return HubFileSuggestion(name: name)

    }

  }

  /// The table that shows each Hub's address, the file to save it as, and the command to use it:
  /// a header row, then a row for each Hub.
  ///
  /// - Parameters:
  ///   - hubs: The Hubs found.
  ///   - directory: The directory of Hub files, or `nil` if it isn't known.
  /// - Returns: The rows, or none when no Hub was found.
  public static func rows(for hubs: [Source], directory: String?) -> [[String]] {

    guard !hubs.isEmpty else {

      return []

    }

    let rows = zip(hubs, suggestions(for: hubs)).map { (hub: Source, suggestion: HubFileSuggestion) -> [String] in

      [
        "\(hub.host):\(hub.port)",
        directory.map { $0 + "/" + suggestion.fileName } ?? suggestion.fileName,
        suggestion.command
      ]

    }

    return [["ADDRESS", "SAVE AS", "USE WITH"]] + rows

  }

  private static func baseName(for hub: Source) -> String {

    let prefix = hub.isHubPro ? "hubpro" : "hub"

    guard let suffix = suffix(for: hub) else {

      return prefix

    }

    return prefix + "-" + suffix

  }

  private static func suffix(for hub: Source) -> String? {

    if let id = hub.insteonID {

      let digits = id.lowercased().filter { $0.isHexDigit && $0.isASCII }

      if digits.count >= 4 {

        return String(digits.suffix(4))

      }

    }

    let groups = hub.host.split(separator: ".", omittingEmptySubsequences: false)

    guard HubName.isAddress(hub.host), let last = groups.last, let number = Int(last) else {

      return nil

    }

    return String(number)

  }

}
