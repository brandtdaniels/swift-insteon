/// The three-byte address that identifies an INSTEON device.
///
/// Every INSTEON device is assigned a unique address at the factory. It is printed on the
/// device as three hexadecimal bytes, for example `1A.2B.3C`.
///
/// ```swift
/// let address = InsteonAddress(0x1A, 0x2B, 0x3C)
/// let parsed = InsteonAddress("1A.2B.3C")   // same address
/// print(address)                            // "1A.2B.3C"
/// ```
public struct InsteonAddress: Hashable, Sendable {

  /// The most significant byte of the address.
  public let high: UInt8

  /// The middle byte of the address.
  public let middle: UInt8

  /// The least significant byte of the address.
  public let low: UInt8

  /// Creates an address from its three bytes.
  ///
  /// - Parameters:
  ///   - high: The most significant byte.
  ///   - middle: The middle byte.
  ///   - low: The least significant byte.
  public init(_ high: UInt8, _ middle: UInt8, _ low: UInt8) {

    self.high = high
    self.middle = middle
    self.low = low

  }

}

// MARK: - ByteEncodable

extension InsteonAddress: ByteEncodable {

  /// The address's three bytes, most significant first.
  public var bytes: [UInt8] {

    [high, middle, low]

  }

}

// MARK: - LosslessStringConvertible

extension InsteonAddress: LosslessStringConvertible {

  /// Parses an address written as six hexadecimal digits.
  ///
  /// The digits may be grouped with periods, as printed on devices (`"1A.2B.3C"`), or
  /// written without separators (`"1A2B3C"`). Parsing is case-insensitive.
  ///
  /// - Parameter description: The text to parse.
  /// - Returns: `nil` if the text is not a valid address.
  public init?(_ description: String) {

    let groups = description.split(separator: ".", omittingEmptySubsequences: false)

    // Either three groups of two digits, or the six digits on their own.
    guard (groups.count == 3 && groups.allSatisfy({ $0.count == 2 })) || groups.count == 1 else {

      return nil

    }

    let digits = Array(groups.joined())

    // `isHexDigit` rules out signs, which `UInt8(_:radix:)` would accept, and
    // `UInt8(_:radix:)` rules out full-width digits, which `isHexDigit` would accept.
    let bytes = digits.count == 6 && digits.allSatisfy(\.isHexDigit)
      ? stride(from: 0, to: 6, by: 2).compactMap { UInt8(String(digits[$0...$0 + 1]), radix: 16) }
      : []

    guard bytes.count == 3 else {

      return nil

    }

    self.init(bytes[0], bytes[1], bytes[2])

  }

  /// The address as three period-separated uppercase hexadecimal bytes, for example `"1A.2B.3C"`.
  public var description: String {

    bytes.map(\.hexDigits).joined(separator: ".")

  }

}
