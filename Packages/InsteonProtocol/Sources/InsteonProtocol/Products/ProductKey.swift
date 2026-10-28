/// A device's INSTEON Product Key (IPK), the 3-byte number that identifies its product.
///
/// The Developer's Guide requires devices made after February 1, 2007 to store their product
/// key and report it in a Product Data Response, which ``ProductData`` reads. Older devices
/// report none. Like a subcategory, a product key names a product only through a device
/// database.
///
/// ```swift
/// let key = ProductKey(0x00, 0x00, 0x1F)
/// print(key)   // "0x00001F"
/// ```
public struct ProductKey: Hashable, Sendable {

  /// The key's most significant byte.
  public var high: UInt8

  /// The key's middle byte.
  public var middle: UInt8

  /// The key's least significant byte.
  public var low: UInt8

  /// Creates a product key from its bytes, most significant first.
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

extension ProductKey: CustomStringConvertible {

  /// The key in hexadecimal, most significant byte first, such as `"0x00001F"`.
  public var description: String {

    "0x" + [high, middle, low].map(\.hexDigits).joined()

  }

}
