/// The three-byte INSTEON Product Key (IPK) that identifies a product model.
///
/// The product key is the primary key of the INSTEON Product Database. A device reports it in
/// its ``ProductData``. Devices without a product key don't report one; identify them by
/// their ``DeviceCategory`` and subcategory instead.
///
/// ```swift
/// let key = InsteonProductKey(0x00, 0x00, 0x34)
/// print(key)   // "0x000034"
/// ```
public struct InsteonProductKey: Hashable, Sendable, ByteEncodable {

  /// The most significant byte of the key.
  public let high: UInt8

  /// The middle byte of the key.
  public let middle: UInt8

  /// The least significant byte of the key.
  public let low: UInt8

  /// Creates a product key from its three bytes.
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

  /// The key's bytes, most significant first.
  public var bytes: [UInt8] {

    [high, middle, low]

  }

}

extension InsteonProductKey: CustomStringConvertible {

  /// The key in hexadecimal, such as `"0x000034"`.
  public var description: String {

    "0x" + hexString

  }

}
