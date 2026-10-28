/// A device's Insteon Device Subcategory (SubCat), which identifies a kind of device within its
/// ``DeviceCategory``.
///
/// Together, the category and subcategory identify a product model, such as a particular
/// dimmer or modem. Names for subcategories come from the Insteon device catalog rather than from this
/// package.
///
/// ```swift
/// let subcategory: DeviceSubcategory = 0x20
/// print(subcategory)   // "0x20"
/// ```
public struct DeviceSubcategory: RawRepresentable, Hashable, Sendable {

  /// The subcategory number.
  public var rawValue: UInt8

  /// Creates a subcategory from its number.
  ///
  /// - Parameter rawValue: The subcategory number.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

}

extension DeviceSubcategory: ExpressibleByIntegerLiteral {

  /// Creates a subcategory from an integer literal, such as `0x20`.
  ///
  /// - Parameter value: The subcategory number.
  public init(integerLiteral value: UInt8) {

    self.init(rawValue: value)

  }

}

extension DeviceSubcategory: CustomStringConvertible {

  /// The subcategory number in hexadecimal, such as `"0x20"`.
  public var description: String {

    "0x" + rawValue.hexDigits

  }

}
