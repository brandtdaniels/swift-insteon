/// What `--hub` and `INSTEON_HUB` take as the name of a Hub file, and what `--hub` takes as an
/// address instead.
///
/// A name is 1 to 32 characters from `a-z`, `0-9`, hyphen and underscore. Nothing else is a
/// name, so a name can't hold a slash or a dot and can't name a file outside the Hub files'
/// directory.
///
/// ```swift
/// HubName.isValid("basement")      // true
/// HubName.isValid("../secrets")    // false
/// HubName.isAddress("192.168.1.20:25105")   // true
/// ```
public enum HubName {

  /// The most characters a name has.
  public static let maximumLength = 32

  /// Whether the text is a Hub's name.
  ///
  /// - Parameter text: A value for `--hub` or `INSTEON_HUB`.
  /// - Returns: `true` for 1 to 32 characters of `a-z`, `0-9`, `-` and `_`.
  public static func isValid(_ text: String) -> Bool {

    let bytes = Array(text.utf8)

    guard (1...maximumLength).contains(bytes.count) else {

      return false

    }

    return bytes.allSatisfy { (byte: UInt8) -> Bool in

      (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
        || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        || byte == UInt8(ascii: "-")
        || byte == UInt8(ascii: "_")

    }

  }

  /// Whether the text has the shape of an IPv4 address, with an optional `:PORT`, such as
  /// `192.168.1.20` or `192.168.1.20:25105`.
  ///
  /// Only the shape is checked: four groups of digits. Whether the address is private, and
  /// whether the port is a port, are checked where the Hub is connected to.
  ///
  /// - Parameter text: A value for `--hub`.
  /// - Returns: `true` if the text is shaped like an IPv4 address.
  public static func isAddress(_ text: String) -> Bool {

    let host = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0]
    let groups = host.split(separator: ".", omittingEmptySubsequences: false)

    return groups.count == 4
      && groups.allSatisfy { (group: Substring) -> Bool in

        (1...3).contains(group.utf8.count) && group.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }

      }

  }

}
