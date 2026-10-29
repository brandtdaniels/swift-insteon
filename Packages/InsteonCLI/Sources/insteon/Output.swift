import Foundation

/// Writes to the terminal. Results go to standard output, and progress, prompts and errors to
/// standard error, so `--json` output can be piped on its own.
///
/// Writes aren't buffered, so `insteon watch` shows each event as it happens even when its
/// output is piped.
enum Output {

  /// Writes a line of results to standard output.
  static func line(_ text: String = "") {

    write(text + "\n", to: .standardOutput)

  }

  /// Writes a line of progress, a prompt or an error to standard error.
  static func note(_ text: String) {

    write(text + "\n", to: .standardError)

  }

  /// Writes a value to standard output as pretty-printed JSON.
  static func json(_ value: some Encodable) throws {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let data = try encoder.encode(value)

    line(String(decoding: data, as: UTF8.self))

  }

  /// Writes rows of columns, each padded to the width of its widest cell.
  static func table(_ rows: [[String]]) {

    guard let columnCount = rows.map(\.count).max() else {

      return

    }

    let widths = (0..<columnCount).map { column in

      rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0

    }

    for row in rows {

      let cells = row.enumerated().map { column, cell in

        column == row.count - 1 ? cell : cell + String(repeating: " ", count: max(0, widths[column] - cell.count))

      }

      line(cells.joined(separator: "  "))

    }

  }

  private static func write(_ text: String, to handle: FileHandle) {

    _ = try? handle.write(contentsOf: Data(text.utf8))

  }

}
