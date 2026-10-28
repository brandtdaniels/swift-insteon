/// A byte as profiles write it: `0x` followed by two uppercase hexadecimal digits.
struct ProfileByte: Decodable {

  let value: UInt8

  init(from decoder: any Decoder) throws {

    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    let digits = text.dropFirst(2)

    guard text.hasPrefix("0x"), digits.count == 2, digits.allSatisfy({ $0.isHexDigit && !$0.isLowercase }), let value = UInt8(digits, radix: 16) else {

      throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(text) isn't 0x followed by two uppercase hexadecimal digits.")

    }

    self.value = value

  }

}
