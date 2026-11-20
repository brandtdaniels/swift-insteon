import Foundation

/// A file that can't be read as text.
public struct TextFileError: Error, CustomStringConvertible, Equatable {
  public let path: String
  public let reason: String

  public init(path: String, reason: String) {
    self.path = path
    self.reason = reason
  }

  public var description: String {
    "\(path): \(reason)"
  }
}

/// Reading text the way Python's `Path.read_text(encoding="utf-8")` does.
public enum TextFile {
  /// The file's text, decoded as UTF-8 with a byte order mark kept, and with each `"\r\n"` and
  /// lone `"\r"` turned into `"\n"`.
  public static func read(_ url: URL) throws -> String {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw TextFileError(path: url.path, reason: "can't be read")
    }
    let text = String(decoding: data, as: UTF8.self)
    // Invalid bytes decode to U+FFFD, so valid input is the one that encodes back to itself.
    guard text.utf8.elementsEqual(data) else {
      throw TextFileError(path: url.path, reason: "isn't valid UTF-8")
    }
    return normalizingNewlines(text)
  }

  /// The text with each `"\r\n"` and lone `"\r"` turned into `"\n"`.
  ///
  /// Swift reads `"\r\n"` as one `Character`, so this works on Unicode scalars.
  public static func normalizingNewlines(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    var previousWasReturn = false
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\r":
        result.append("\n")
        previousWasReturn = true
      case "\n":
        if !previousWasReturn {
          result.append("\n")
        }
        previousWasReturn = false
      default:
        result.append(scalar)
        previousWasReturn = false
      }
    }
    return String(result)
  }
}
