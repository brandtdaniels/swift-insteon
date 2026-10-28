/// A device's Insteon Product Key (IPK), the 3-byte number that identifies its product.
///
/// The Insteon Developer's Guide requires devices made after February 1, 2007 to store their
/// product key and report it in a Product Data Response, which ``ProductData`` reads. In practice
/// the key wasn't kept up: later sources mark the Product Data Request as no longer used, and many
/// devices, newer ones especially, don't fill the key in. Identify a device by its
/// ``DeviceCategory``, ``DeviceSubcategory`` and ``FirmwareVersion`` instead, and treat the key as
/// a value the device happened to report.
///
/// ```swift
/// let key = ProductKey(0x00, 0x00, 0x1F)
/// print(key)   // "0x00001F"
/// ```
public struct ProductKey: Hashable, Sendable {

  /// The key's most significant byte.
  public let high: UInt8

  /// The key's middle byte.
  public let middle: UInt8

  /// The key's least significant byte.
  public let low: UInt8

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

extension ProductKey: ByteEncodable {

  /// The key's bytes, most significant first, as a Product Data Response carries them.
  public var bytes: [UInt8] {

    [high, middle, low]

  }

}

extension ProductKey: CustomStringConvertible {

  /// The key in hexadecimal, most significant byte first, such as `"0x00001F"`.
  public var description: String {

    "0x" + hexString

  }

}
