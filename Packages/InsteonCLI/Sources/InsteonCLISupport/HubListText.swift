/// The words `insteon hubs` prints for a ``HubListing``.
public enum HubListText {

  /// The table: a header row, then a row for each file with its name, address and a note.
  ///
  /// - Parameter listing: The Hub files.
  /// - Returns: The rows, or none when there are no files to list. A row with nothing to note
  ///   has no third cell.
  public static func rows(for listing: HubListing) -> [[String]] {

    guard !listing.entries.isEmpty else {

      return []

    }

    return [["NAME", "ADDRESS", "NOTE"]] + listing.entries.map { (entry: HubListing.Entry) -> [String] in

      let cells = [entry.name ?? "(default file)", entry.address ?? "-"]
      let note = note(for: entry)

      return note.isEmpty ? cells : cells + [note]

    }

  }

  /// What to print when there are no files: where the command looked and how to create one.
  ///
  /// - Parameter listing: The Hub files.
  /// - Returns: The message.
  public static func emptyMessage(for listing: HubListing) -> String {

    let place = listing.directory ?? "the directory of Hub files, which can't be found because neither XDG_CONFIG_HOME nor HOME is set"

    return "No Hub files in \(place). Create NAME.env there with INSTEON_HUB_USERNAME, INSTEON_HUB_PASSWORD and INSTEON_HUB_HOST, make it readable only by you with chmod 600, and use it with 'insteon --hub NAME'."

  }

  /// Lines to print after the table.
  ///
  /// - Parameter listing: The Hub files.
  /// - Returns: The lines, none when there's nothing to add.
  public static func notes(for listing: HubListing) -> [String] {

    guard let name = listing.missingVariableHub, let directory = listing.directory else {

      return []

    }

    return ["INSTEON_HUB names '\(name)', but \(directory)/\(name).env doesn't exist."]

  }

  private static func note(for entry: HubListing.Entry) -> String {

    if let problem = entry.problem {

      return text(for: problem, path: entry.path)

    }

    if entry.isReadableByOthers {

      return "others can read it; chmod 600 \(entry.path)"

    }

    if entry.address == nil {

      return "no INSTEON_HUB_HOST; give --hub ADDRESS"

    }

    return entry.isDefault ? "default" : ""

  }

  private static func text(for problem: HubListing.Problem, path: String) -> String {

    switch problem {
    case .refused(.writableByOthers):
      "not read: others can write to it; chmod 600 \(path)"
    case .refused(.ownedByAnotherUser):
      "not read: another user owns it"
    case .refused(.notRegularFile):
      "not read: it isn't a regular file"
    case .unreadable:
      "not read: it can't be opened or isn't UTF-8 text"
    case let .malformed(line):
      "not read: line \(line) isn't NAME=VALUE"
    case .unusableName:
      "unusable name: use a-z, 0-9, hyphen and underscore, 1 to 32 characters"
    }

  }

}
