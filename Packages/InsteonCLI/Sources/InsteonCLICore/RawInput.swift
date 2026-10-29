import InsteonProtocol

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

/// Which serial commands `insteon modem send` writes without `--force`.
public enum SerialCommandPolicy {

  /// Why a serial command is refused without `--force`, or `nil` if it isn't.
  ///
  /// A command that doesn't start with `0x02` is always refused, so this isn't asked about it.
  /// One whose number the package doesn't know is refused, since the modem's answer can't be
  /// read. So are those that change or erase what the modem keeps, or stop it answering: Set
  /// Host Device Category, Reset the IM, Set IM Configuration, Manage ALL-Link Record, RF
  /// Sleep, Write Database, Set Radio and Manage Device Record.
  ///
  /// - Parameter bytes: The command's bytes, starting with `0x02`.
  /// - Returns: The reason, as a sentence.
  public static func refusal(for bytes: [UInt8]) -> String? {

    guard bytes.count >= 2 else {

      return "A serial command needs its number after 0x02."

    }

    let number: UInt8 = bytes[1]

    guard SerialCommandNumber(rawValue: number) != nil else {

      return "\(Hex.byte(number)) isn't a serial command the package knows, so the modem's answer can't be read."

    }

    switch number {
    case 0x66:
      return "Set Host Device Category (0x66) changes the identity the modem reports."
    case 0x67:
      return "Reset the IM (0x67) erases the modem's ALL-Link database and configuration."
    case 0x6B:
      return "Set IM Configuration (0x6B) can turn off the modem's linking and the messages it passes on."
    case 0x6F:
      return "Manage ALL-Link Record (0x6F) can change or delete the modem's ALL-Link records."
    case 0x72:
      return "RF Sleep (0x72) puts the modem to sleep, so it stops answering."
    case 0x76:
      return "Write Database (0x76) overwrites the modem's ALL-Link database."
    case 0x7D:
      return "Set Radio (0x7D) can turn off the modem's radio until it's turned back on."
    case 0x82:
      return "Manage Device Record (0x82) can change or delete a record in a device's ALL-Link database."
    default:
      return nil
    }

  }

}
