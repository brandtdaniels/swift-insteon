/// A value with a fixed binary representation in the Insteon protocol.
public protocol ByteEncodable {

  /// The value's bytes, in the order they are transmitted.
  var bytes: [UInt8] { get }

}

extension ByteEncodable {

  /// The value's bytes as uppercase hexadecimal, two digits per byte, with no separators.
  ///
  /// This is the form Insteon modems and hubs accept in their text interfaces,
  /// for example `"0F1180"`.
  public var hexString: String {

    bytes.map(\.hexDigits).joined()

  }

}

extension UInt8 {

  /// The byte as two uppercase hexadecimal digits.
  package var hexDigits: String {

    let digits = String(self, radix: 16, uppercase: true)

    return self < 0x10 ? "0" + digits : digits

  }

}

extension UInt16 {

  /// Creates a value from its two bytes, most significant first.
  init(highByte: UInt8, lowByte: UInt8) {

    self = UInt16(highByte) << 8 | UInt16(lowByte)

  }

  /// The value's two bytes, most significant first.
  var bigEndianBytes: [UInt8] {

    [UInt8(self >> 8), UInt8(self & 0xFF)]

  }

}
