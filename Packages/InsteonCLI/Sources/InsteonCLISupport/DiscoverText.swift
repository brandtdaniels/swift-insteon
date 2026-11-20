/// A Hub `insteon discover` found, as the command lists it.
public struct DiscoveredHub: Hashable, Sendable {

  /// The Hub's product, such as `Hub 2245`, if known.
  public var product: String?

  /// The Hub's host.
  public var host: String

  /// The port of the Hub's interface.
  public var port: Int

  /// The Hub's Insteon ID, such as `1A.2B.3C`, if known.
  public var insteonID: String?

  /// How the Hub was found, as the labels the command shows.
  public var foundBy: [String]

  /// Whether the Hub is a Hub Pro, which needs no login.
  public var isHubPro: Bool

  /// Creates a found Hub.
  ///
  /// - Parameters:
  ///   - product: The Hub's product, if known.
  ///   - host: The Hub's host.
  ///   - port: The port of the Hub's interface.
  ///   - insteonID: The Hub's Insteon ID, if known.
  ///   - foundBy: How the Hub was found, as labels.
  ///   - isHubPro: Whether the Hub is a Hub Pro.
  public init(product: String?, host: String, port: Int, insteonID: String?, foundBy: [String], isHubPro: Bool) {

    self.product = product
    self.host = host
    self.port = port
    self.insteonID = insteonID
    self.foundBy = foundBy
    self.isHubPro = isHubPro

  }

}

/// A Hub file that already exists, as `insteon hubs` lists it.
public struct SavedHubFile: Hashable, Sendable {

  /// The Hub's name: the file's name without `.env`.
  public var name: String

  /// The address the file sets, as `HOST` or `HOST:PORT`.
  public var address: String

  /// Creates a saved Hub file.
  ///
  /// - Parameters:
  ///   - name: The Hub's name.
  ///   - address: The address the file sets.
  public init(name: String, address: String) {

    self.name = name
    self.address = address

  }

}

/// The text `insteon discover` prints for the Hubs it found: one table of Hubs, then for each
/// Hub the file to save its settings in and the command that uses it, or the name it's already
/// saved as.
public enum DiscoverText {

  /// The longest line the text makes.
  public static let width: Int = 100

  /// The port a Hub 2 and a Hub 1 listen on, which a file leaves out.
  static let defaultPort: Int = 25_105

  /// The lines to print for the Hubs found, none when there are none.
  ///
  /// A directory under `home` is shown with a leading `~`. A Hub whose file exists in `saved`,
  /// found by its address, is shown with the name it's saved as instead of how to save it.
  ///
  /// - Parameters:
  ///   - hubs: The Hubs found.
  ///   - directory: The directory of Hub files, or `nil` if it isn't known.
  ///   - home: The home directory, or `nil` if it isn't known.
  ///   - saved: The Hub files that exist.
  /// - Returns: The lines, none longer than ``width`` unless one word is.
  public static func lines(for hubs: [DiscoveredHub], directory: String?, home: String?, saved: [SavedHubFile]) -> [String] {

    guard !hubs.isEmpty else {

      return []

    }

    let sources: [HubFileSuggestion.Source] = hubs.map { (hub: DiscoveredHub) -> HubFileSuggestion.Source in

      HubFileSuggestion.Source(isHubPro: hub.isHubPro, insteonID: hub.insteonID, host: hub.host, port: hub.port)

    }
    let suggestions: [HubFileSuggestion] = HubFileSuggestion.suggestions(for: sources)
    var lines: [String] = ["Found \(Wording.count(hubs.count, "Hub")):", ""]

    lines += table(hubs).map { (row: String) -> String in "  " + row }

    let entries: [(hub: DiscoveredHub, suggestion: HubFileSuggestion, savedAs: String?)] = zip(hubs, suggestions).map { pair in

      (pair.0, pair.1, saved.first { (file: SavedHubFile) -> Bool in matches(file, pair.0) }?.name)

    }
    let unsaved = entries.filter { $0.savedAs == nil }
    let nameWidth: Int = unsaved.map { $0.suggestion.name.count }.max() ?? 0

    if !unsaved.isEmpty {

      lines += ["", "To use a Hub by name, save its settings in a file readable only by you:"]

    }

    for entry in entries {

      lines.append("")

      if let name = entry.savedAs {

        lines.append("  \(entry.hub.host):\(entry.hub.port)  already saved as \(name)")
        lines.append("    then: insteon --hub \(name) info")

        continue

      }

      lines += block(for: entry.hub, suggestion: entry.suggestion, nameWidth: nameWidth, path: path(of: entry.suggestion, directory: directory, home: home))

    }

    var footer: [String] = []

    if hubs.contains(where: \.isHubPro) {

      footer += CatalogRefusalText.wrap("A Hub Pro's devices are linked with its Set buttons; insteon reads and controls them.")

    }

    if !unsaved.isEmpty {

      footer += CatalogRefusalText.wrap(
        "A Hub Pro takes no login. A Hub 2 or Hub 1 also needs INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD "
          + "(its login, from its label or the Insteon app); never type them on the command line."
      )

    }

    if !footer.isEmpty {

      lines.append("")
      lines += footer

    }

    return lines

  }

  /// The table of Hubs: the product, address, Insteon ID and found-by columns, leaving out a column no Hub
  /// has a value for, and showing `-` where only some do. No cell is padded past the last column.
  private static func table(_ hubs: [DiscoveredHub]) -> [String] {

    let columns: [(title: String, cell: (DiscoveredHub) -> String?)] = [
      ("PRODUCT", { $0.product }),
      ("ADDRESS", { "\($0.host):\($0.port)" }),
      ("INSTEON ID", { $0.insteonID }),
      ("FOUND BY", { $0.foundBy.isEmpty ? nil : $0.foundBy.joined(separator: ", ") }),
    ].filter { (column: (title: String, cell: (DiscoveredHub) -> String?)) -> Bool in hubs.contains { column.cell($0) != nil } }
    let rows: [[String]] = [columns.map(\.title)] + hubs.map { (hub: DiscoveredHub) -> [String] in

      columns.map { (column: (title: String, cell: (DiscoveredHub) -> String?)) -> String in column.cell(hub) ?? "-" }

    }
    let widths: [Int] = columns.indices.map { (index: Int) -> Int in rows.map { $0[index].count }.max() ?? 0 }

    return rows.map { (row: [String]) -> String in

      row.enumerated().map { (index: Int, cell: String) -> String in

        index == row.count - 1 ? cell : cell + String(repeating: " ", count: widths[index] - cell.count + 2)

      }.joined()

    }

  }

  /// The block that says what to save for a Hub: the name and path, the lines for the file, and
  /// the commands.
  private static func block(for hub: DiscoveredHub, suggestion: HubFileSuggestion, nameWidth: Int, path: String) -> [String] {

    var lines: [String] = []
    let name: String = "  " + suggestion.name
    let padded: String = name + String(repeating: " ", count: nameWidth - suggestion.name.count) + "   " + path

    if padded.count <= width {

      lines.append(padded)

    } else {

      lines += [name, "    " + path]

    }

    lines.append("    INSTEON_HUB_HOST=\(hub.host)")

    if !hub.isHubPro {

      if hub.port != defaultPort {

        lines.append("    INSTEON_HUB_PORT=\(hub.port)")

      }

      lines.append("    INSTEON_HUB_USERNAME=<the Hub's username>")
      lines.append("    INSTEON_HUB_PASSWORD=<the Hub's password>")

      let chmod: String = "    then: chmod 600 \(path)"

      lines += chmod.count <= width ? [chmod] : ["    then: chmod 600", "      " + path]

    }

    lines.append("    then: \(suggestion.command)")

    return lines

  }

  /// The file's path, with a leading `~` for a directory under the home directory.
  private static func path(of suggestion: HubFileSuggestion, directory: String?, home: String?) -> String {

    guard var directory else {

      return suggestion.fileName

    }

    if let home, !home.isEmpty, directory.hasPrefix(home + "/") {

      directory = "~" + directory.dropFirst(home.count)

    }

    return directory + "/" + suggestion.fileName

  }

  private static func matches(_ file: SavedHubFile, _ hub: DiscoveredHub) -> Bool {

    file.address == "\(hub.host):\(hub.port)" || file.address == hub.host

  }

}
