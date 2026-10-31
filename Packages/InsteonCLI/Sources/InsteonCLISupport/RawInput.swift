/// Reads the bytes people type for `insteon device ADDRESS send` and `insteon modem send`.
///
/// ```swift
/// HexInput.byte("0x2E")         // 0x2E
/// HexInput.bytes("02 77 01")    // [0x02, 0x77, 0x01]
/// ```
public enum HexInput {

  /// A byte as one or two hexadecimal digits, with or without `0x`, such as `0x30` or `30`.
  ///
  /// - Parameter text: The text.
  /// - Returns: The byte, or `nil` if the text isn't one.
  public static func byte(_ text: String) -> UInt8? {

    let digits: Substring = text.hasPrefix("0x") || text.hasPrefix("0X") ? text.dropFirst(2) : Substring(text)

    guard (1...2).contains(digits.count), digits.allSatisfy(\.isHexDigit) else {

      return nil

    }

    return UInt8(digits, radix: 16)

  }

  /// Bytes as pairs of hexadecimal digits, run together or apart, each group with or without
  /// `0x`, such as `0277`, `02 77 01` or `0x02 0x77`.
  ///
  /// - Parameter text: The text.
  /// - Returns: The bytes, or `nil` if the text has no digits, an odd number of them, or
  ///   anything else.
  public static func bytes(_ text: String) -> [UInt8]? {

    var digits: [Character] = []

    for group in text.split(whereSeparator: \.isWhitespace) {

      let body: Substring = group.hasPrefix("0x") || group.hasPrefix("0X") ? group.dropFirst(2) : group

      guard !body.isEmpty, body.count % 2 == 0, body.allSatisfy(\.isHexDigit) else {

        return nil

      }

      digits += body

    }

    guard !digits.isEmpty else {

      return nil

    }

    return stride(from: 0, to: digits.count, by: 2).compactMap { (index: Int) -> UInt8? in

      UInt8(String(digits[index...index + 1]), radix: 16)

    }

  }

}
