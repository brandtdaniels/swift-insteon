/// Validation of JSON text as Python's `json.loads` reads it, so a file one rejects the other
/// rejects too.
///
/// It accepts exactly one JSON value (RFC 8259) with the whitespace JSON allows around it, and
/// also `NaN`, `Infinity` and `-Infinity`, which Python reads. It refuses a byte order mark,
/// comments, trailing commas, raw control characters in strings, bad escapes, leading zeros and
/// bytes that aren't UTF-8.
public enum StrictJSON {
  /// Throws a `CheckFailure` naming the file if the bytes aren't one JSON value.
  public static func validate(_ bytes: [UInt8], named name: String) throws {
    let text = String(decoding: bytes, as: UTF8.self)
    guard text.utf8.elementsEqual(bytes) else {
      throw CheckFailure("\(name): isn't valid JSON: not UTF-8")
    }

    var reader = Reader(scalars: Array(text.unicodeScalars))
    do {
      try reader.readDocument()
    } catch let problem as Problem {
      throw CheckFailure("\(name): isn't valid JSON: \(problem.reason) at position \(problem.position)")
    }
  }

  private struct Problem: Error {
    let reason: String
    let position: Int
  }

  private struct Reader {
    let scalars: [Unicode.Scalar]
    var index = 0
    var depth = 0

    init(scalars: [Unicode.Scalar]) {
      self.scalars = scalars
    }

    func fail(_ reason: String) -> Problem {
      Problem(reason: reason, position: index)
    }

    mutating func readDocument() throws {
      if scalars.first == "\u{FEFF}" {
        throw fail("unexpected byte order mark")
      }
      skipWhitespace()
      try readValue()
      skipWhitespace()
      if index < scalars.count {
        throw fail("extra data")
      }
    }

    mutating func skipWhitespace() {
      while index < scalars.count, scalars[index] == " " || scalars[index] == "\t" || scalars[index] == "\n" || scalars[index] == "\r" {
        index += 1
      }
    }

    mutating func readValue() throws {
      guard index < scalars.count else {
        throw fail("expected a value")
      }

      switch scalars[index] {
      case "{": try readObject()
      case "[": try readArray()
      case "\"": try readString()
      case "-", "0"..."9": try readNumber()
      default:
        for word in ["true", "false", "null", "NaN", "Infinity"] where consume(word) {
          return
        }
        throw fail("expected a value")
      }
    }

    mutating func consume(_ word: String) -> Bool {
      let pattern = Array(word.unicodeScalars)
      guard index + pattern.count <= scalars.count, scalars[index..<index + pattern.count].elementsEqual(pattern) else {
        return false
      }
      index += pattern.count
      return true
    }

    mutating func enter() throws {
      depth += 1
      if depth > 900 {
        throw fail("nested too deeply")
      }
    }

    mutating func readObject() throws {
      try enter()
      defer { depth -= 1 }
      index += 1
      skipWhitespace()
      if index < scalars.count, scalars[index] == "}" {
        index += 1
        return
      }
      while true {
        skipWhitespace()
        guard index < scalars.count, scalars[index] == "\"" else {
          throw fail("expected a property name in double quotes")
        }
        try readString()
        skipWhitespace()
        guard index < scalars.count, scalars[index] == ":" else {
          throw fail("expected ':'")
        }
        index += 1
        skipWhitespace()
        try readValue()
        skipWhitespace()
        guard index < scalars.count else {
          throw fail("expected ',' or '}'")
        }
        if scalars[index] == "," {
          index += 1
        } else if scalars[index] == "}" {
          index += 1
          return
        } else {
          throw fail("expected ',' or '}'")
        }
      }
    }

    mutating func readArray() throws {
      try enter()
      defer { depth -= 1 }
      index += 1
      skipWhitespace()
      if index < scalars.count, scalars[index] == "]" {
        index += 1
        return
      }
      while true {
        skipWhitespace()
        try readValue()
        skipWhitespace()
        guard index < scalars.count else {
          throw fail("expected ',' or ']'")
        }
        if scalars[index] == "," {
          index += 1
        } else if scalars[index] == "]" {
          index += 1
          return
        } else {
          throw fail("expected ',' or ']'")
        }
      }
    }

    mutating func readString() throws {
      index += 1
      while index < scalars.count {
        let scalar = scalars[index]
        if scalar == "\"" {
          index += 1
          return
        }
        if scalar.value < 0x20 {
          throw fail("invalid control character")
        }
        if scalar == "\\" {
          index += 1
          guard index < scalars.count else { break }
          switch scalars[index] {
          case "\"", "\\", "/", "b", "f", "n", "r", "t":
            index += 1
          case "u":
            index += 1
            for _ in 0..<4 {
              guard index < scalars.count, scalars[index].properties.isASCIIHexDigit else {
                throw fail("invalid \\u escape")
              }
              index += 1
            }
          default:
            throw fail("invalid escape")
          }
        } else {
          index += 1
        }
      }
      throw fail("unterminated string")
    }

    mutating func readNumber() throws {
      if scalars[index] == "-" {
        index += 1
        if consume("Infinity") {
          return
        }
      }
      guard index < scalars.count, ("0"..."9").contains(scalars[index]) else {
        throw fail("expected a digit")
      }
      if scalars[index] == "0" {
        index += 1
      } else {
        skipDigits()
      }
      if index < scalars.count, scalars[index] == ".", index + 1 < scalars.count, ("0"..."9").contains(scalars[index + 1]) {
        index += 1
        skipDigits()
      }
      if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
        var look = index + 1
        if look < scalars.count, scalars[look] == "+" || scalars[look] == "-" {
          look += 1
        }
        if look < scalars.count, ("0"..."9").contains(scalars[look]) {
          index = look
          skipDigits()
        }
      }
    }

    mutating func skipDigits() {
      while index < scalars.count, ("0"..."9").contains(scalars[index]) {
        index += 1
      }
    }
  }
}
