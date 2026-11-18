/// Python's `repr` of a string, which the messages quote their matches with.
public enum PythonRepr {
  /// The text in single quotes, or in double quotes if it holds an apostrophe and no double
  /// quote, with the escapes Python writes.
  public static func of(_ text: String) -> String {
    let scalars = text.unicodeScalars
    let hasSingle = scalars.contains("'")
    let hasDouble = scalars.contains("\"")
    let quote: Unicode.Scalar = hasSingle && !hasDouble ? "\"" : "'"

    var result = String.UnicodeScalarView()
    result.append(quote)

    for scalar in scalars {
      switch scalar {
      case quote, "\\":
        result.append("\\")
        result.append(scalar)
      case "\t":
        result.append(contentsOf: "\\t".unicodeScalars)
      case "\n":
        result.append(contentsOf: "\\n".unicodeScalars)
      case "\r":
        result.append(contentsOf: "\\r".unicodeScalars)
      default:
        if isPrintable(scalar) {
          result.append(scalar)
        } else {
          result.append(contentsOf: escape(scalar).unicodeScalars)
        }
      }
    }

    result.append(quote)
    return String(result)
  }

  /// Python's `str.isprintable` for one scalar: not a control, format, surrogate, private-use,
  /// unassigned or separator character, except the space.
  static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
    if scalar == " " {
      return true
    }
    switch scalar.properties.generalCategory {
    case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator, .spaceSeparator:
      return false
    default:
      return true
    }
  }

  private static func escape(_ scalar: Unicode.Scalar) -> String {
    let value = scalar.value
    let digits = String(value, radix: 16)
    let width: Int
    let marker: String
    switch value {
    case 0...0xFF:
      (marker, width) = ("\\x", 2)
    case 0x100...0xFFFF:
      (marker, width) = ("\\u", 4)
    default:
      (marker, width) = ("\\U", 8)
    }
    return marker + String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}
