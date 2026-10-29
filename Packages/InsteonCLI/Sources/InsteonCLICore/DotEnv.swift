/// Reads a `.env` file of environment variables, such as the Hub's credentials.
///
/// Each line is `KEY=VALUE`, optionally after `export `. Blank lines and lines starting with
/// `#` are ignored. A value may be wrapped in matching single or double quotes, which are
/// removed; nothing else in it is interpreted, so `$`, `\` and `#` are kept as they are, and
/// there are no comments after a value.
///
/// ```swift
/// let variables = try DotEnv.parse("""
///   # The Hub's credentials, printed on it.
///   INSTEON_HUB_USERNAME=example-user
///   INSTEON_HUB_PASSWORD="example password"
///   """)
/// ```
public enum DotEnv {

  /// The name of the file the `insteon` command reads from the current directory: `.env`.
  public static let fileName = ".env"

  /// Reads the variables in a `.env` file's contents.
  ///
  /// - Parameter contents: The file's contents.
  /// - Returns: The variables. A key given twice takes its last value.
  /// - Throws: ``DotEnvError/malformedLine(_:)`` for a line that isn't `KEY=VALUE`, has a key
  ///   that isn't letters, digits and underscores starting with a letter or underscore, or has
  ///   an unclosed quote.
  public static func parse(_ contents: String) throws(DotEnvError) -> [String: String] {

    var variables: [String: String] = [:]

    // "\r\n" is one Character, and a newline, so Windows line endings split the same way.
    let lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

    for (offset, rawLine) in lines.enumerated() {

      let lineNumber = offset + 1
      var line = trimmed(rawLine)

      if line.isEmpty || line.hasPrefix("#") {

        continue

      }

      if line.hasPrefix("export ") {

        line = trimmed(line.dropFirst("export ".count))

      }

      guard let equals = line.firstIndex(of: "=") else {

        throw DotEnvError.malformedLine(lineNumber)

      }

      let key = trimmed(line[..<equals])

      guard isValidKey(key) else {

        throw DotEnvError.malformedLine(lineNumber)

      }

      guard let value = unquoted(trimmed(line[line.index(after: equals)...])) else {

        throw DotEnvError.malformedLine(lineNumber)

      }

      variables[String(key)] = String(value)

    }

    return variables

  }

  /// Merges a `.env` file's variables into the process's environment. A variable set in the
  /// environment wins over the file, so the file holds defaults that can be overridden.
  ///
  /// - Parameters:
  ///   - fileVariables: The variables read from the file.
  ///   - environment: The process's environment.
  /// - Returns: The merged environment.
  public static func merging(_ fileVariables: [String: String], into environment: [String: String]) -> [String: String] {

    environment.merging(fileVariables) { current, _ in current }

  }

  private static func trimmed(_ text: Substring) -> Substring {

    let start = text.drop(while: \.isWhitespace)
    var end = start.endIndex

    while end > start.startIndex, start[start.index(before: end)].isWhitespace {

      end = start.index(before: end)

    }

    return start[..<end]

  }

  private static func isValidKey(_ key: Substring) -> Bool {

    guard let first = key.first, first == "_" || (first.isASCII && first.isLetter) else {

      return false

    }

    return key.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }

  }

  /// The value without the matching quotes around it, or `nil` if it opens a quote it doesn't
  /// close.
  private static func unquoted(_ value: Substring) -> Substring? {

    guard let first = value.first, first == "\"" || first == "'" else {

      return value

    }

    guard value.count >= 2, value.last == first else {

      return nil

    }

    return value.dropFirst().dropLast()

  }

}

/// A `.env` file the `insteon` command can't read.
///
/// The error names only the line, never its text, which may hold a password.
public enum DotEnvError: Error, Hashable, Sendable {

  /// The line, counting from 1, isn't `KEY=VALUE`.
  case malformedLine(Int)

}

extension DotEnvError: CustomStringConvertible {

  /// The error as a one-line message for the person who typed the command.
  public var description: String {

    switch self {
    case let .malformedLine(line):
      "Line \(line) of \(DotEnv.fileName) isn't KEY=VALUE."
    }

  }

}
