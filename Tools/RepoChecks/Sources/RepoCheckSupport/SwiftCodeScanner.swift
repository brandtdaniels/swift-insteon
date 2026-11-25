/// A line of Swift source reduced to its code.
public struct CodeLine: Equatable, Sendable {
  /// The line's number, from 1.
  public let number: Int

  /// The line's code without comments or string literals. A string literal becomes `""`,
  /// followed by the code of its interpolations.
  public let code: String

  /// The source of each interpolation read on the line, innermost first, each from after its
  /// `\(` to its closing parenthesis.
  public let interpolations: [String]

  /// Whether an interpolation reaches the end of the line without closing.
  public let hasUnclosedInterpolation: Bool
}

/// Reads Swift source line by line, leaving out comments (nested ones too) and the insides of
/// string literals (raw and multiline ones too), but keeping what an interpolation holds so a
/// comparison can't hide in one.
///
/// It works on Unicode scalars, as the Python script it replaces worked on code points.
public enum SwiftCodeScanner {
  /// Each line of the text, as its code.
  public static func lines(in text: String) -> [CodeLine] {
    var scanner = Scanner()
    return PythonText.splitLines(text).enumerated().map { offset, line in
      scanner.scan(line: line, number: offset + 1)
    }
  }

  private struct Scanner {
    var commentDepth = 0
    /// The number of `#` around the multiline string the line is in, or nil outside one.
    var multilineHashes: Int?

    mutating func scan(line text: String, number: Int) -> CodeLine {
      let line = Array(text.unicodeScalars)
      var reader = LineReader(line: line)
      var code = String.UnicodeScalarView()
      var index = 0

      while index < line.count {
        if commentDepth > 0 {
          let opening = find("/*", in: line, from: index)
          let closing = find("*/", in: line, from: index)

          if closing == nil && opening == nil {
            index = line.count
          } else if let opening, closing == nil || opening < closing! {
            commentDepth += 1
            index = opening + 2
          } else if let closing {
            commentDepth -= 1
            index = closing + 2
          }
          continue
        }

        if let hashes = multilineHashes {
          let (after, interpolations, closed) = reader.scanString(
            from: index, closing: "\"\"\"", hashes: hashes)
          index = after
          code.append(contentsOf: interpolations.unicodeScalars)
          if closed {
            multilineHashes = nil
            code.append(contentsOf: "\"\"".unicodeScalars)
          }
          continue
        }

        if starts(line, "//", at: index) {
          break
        }

        if starts(line, "/*", at: index) {
          commentDepth = 1
          index += 2
          continue
        }

        if let opening = stringOpening(in: line, at: index) {
          index += opening.hashes + (opening.multiline ? 3 : 1)

          if opening.multiline {
            multilineHashes = opening.hashes
            continue
          }

          let (after, interpolations, _) = reader.scanString(
            from: index, closing: "\"", hashes: opening.hashes)
          index = after
          code.append(contentsOf: "\"\"".unicodeScalars)
          code.append(contentsOf: interpolations.unicodeScalars)
          continue
        }

        code.append(line[index])
        index += 1
      }

      return CodeLine(
        number: number,
        code: String(code),
        interpolations: reader.interpolations,
        hasUnclosedInterpolation: reader.hasUnclosed
      )
    }
  }

  /// Reads the strings and interpolations of one line, remembering each interpolation.
  private struct LineReader {
    let line: Scalars
    var interpolations: [String] = []
    var hasUnclosed = false

    init(line: Scalars) {
      self.line = line
    }

    /// Reads a string literal's contents from `index` to its closing quotes, skipping escapes.
    ///
    /// Returns the index after the closing quotes, or the line's end; the code of the
    /// interpolations, each followed by a space; and whether the string closed on the line.
    mutating func scanString(from start: Int, closing: String, hashes: Int) -> (Int, String, Bool) {
      var index = start
      var found = String.UnicodeScalarView()
      let hashRun = String(repeating: "#", count: hashes)
      let escape = "\\" + hashRun
      let end = closing + hashRun

      while index < line.count {
        if starts(line, escape + "(", at: index) {
          let (after, inner) = interpolation(from: index + escape.unicodeScalars.count + 1)
          found.append(contentsOf: (inner + " ").unicodeScalars)
          index = after
          continue
        }

        if starts(line, escape, at: index) {
          index += escape.unicodeScalars.count + 1
          continue
        }

        if starts(line, end, at: index) {
          return (index + end.unicodeScalars.count, String(found), true)
        }

        index += 1
      }

      return (index, String(found), false)
    }

    /// Reads an interpolation's code from `index`, after its `\(`, to its closing parenthesis.
    ///
    /// Returns the index after the parenthesis and the code, with its own string literals as
    /// `""` followed by their interpolations. An interpolation that isn't closed on its line is
    /// read to the line's end and marks the line.
    mutating func interpolation(from start: Int) -> (Int, String) {
      var index = start
      var depth = 0
      var code = String.UnicodeScalarView()

      while index < line.count {
        let character = line[index]

        var hashes = 0
        while index + hashes < line.count, line[index + hashes] == "#" {
          hashes += 1
        }

        if index + hashes < line.count, line[index + hashes] == "\"" {
          let (after, inner, _) = scanString(
            from: index + hashes + 1, closing: "\"", hashes: hashes)
          index = after
          code.append(contentsOf: "\"\"".unicodeScalars)
          code.append(contentsOf: inner.unicodeScalars)
          continue
        }

        if character == "(" {
          depth += 1
        } else if character == ")" {
          if depth == 0 {
            interpolations.append(String(String.UnicodeScalarView(line[start...index])))
            return (index + 1, String(code))
          }
          depth -= 1
        }

        code.append(character)
        index += 1
      }

      hasUnclosed = true
      interpolations.append(String(String.UnicodeScalarView(line[start...])))
      return (index, String(code))
    }
  }

}

/// Whether the line has the text at the index.
private func starts(_ line: Scalars, _ text: String, at index: Int) -> Bool {
  let pattern = Array(text.unicodeScalars)
  guard index >= 0, index + pattern.count <= line.count else {
    return false
  }
  return line[index..<index + pattern.count].elementsEqual(pattern)
}

private func find(_ text: String, in line: Scalars, from index: Int) -> Int? {
  var position = index
  while position < line.count {
    if starts(line, text, at: position) {
      return position
    }
    position += 1
  }
  return nil
}

/// A string literal's opening quotes at the index: its `#` count, and whether it is the
/// multiline `"""`.
private func stringOpening(in line: Scalars, at index: Int) -> (hashes: Int, multiline: Bool)? {
  var hashes = 0
  while index + hashes < line.count, line[index + hashes] == "#" {
    hashes += 1
  }
  guard index + hashes < line.count, line[index + hashes] == "\"" else {
    return nil
  }
  return (hashes, starts(line, "\"\"\"", at: index + hashes))
}

private typealias Scalars = [Unicode.Scalar]
