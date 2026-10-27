/// A device's INSTEON Device Category (DevCat), such as `0x01` for dimmable lighting control.
///
/// The category groups devices that share a family of commands: what a direct command means
/// depends on the category of the device that receives it. Together with the device
/// subcategory (SubCat), it identifies a kind of device. Names and descriptions for categories
/// come from a device database rather than from this package.
///
/// ```swift
/// let dimmable: DeviceCategory = 0x01
/// print(dimmable)   // "0x01"
/// ```
public struct DeviceCategory: RawRepresentable, Hashable, Sendable {

  /// The category number.
  public var rawValue: UInt8

  /// Creates a category from its number.
  ///
  /// - Parameter rawValue: The category number.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

}

extension DeviceCategory: ExpressibleByIntegerLiteral {

  /// Creates a category from an integer literal, such as `0x01`.
  ///
  /// - Parameter value: The category number.
  public init(integerLiteral value: UInt8) {

    self.init(rawValue: value)

  }

}

extension DeviceCategory: CustomStringConvertible {

  /// The category number in hexadecimal, such as `"0x01"`.
  public var description: String {

    "0x" + rawValue.hexDigits

  }

}
