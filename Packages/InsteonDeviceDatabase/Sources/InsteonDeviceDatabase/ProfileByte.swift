import InsteonProtocol

/// A byte as profiles write it: `0x` followed by two uppercase hexadecimal digits.
struct ProfileByte: Decodable {

  let value: UInt8

  init(from decoder: any Decoder) throws {

    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)

    // Writing the value back out rejects every other spelling, such as lowercase digits.
    guard text.hasPrefix("0x"), let value = UInt8(text.dropFirst(2), radix: 16), "0x" + value.hexDigits == text else {

      throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(text) isn't 0x followed by two uppercase hexadecimal digits.")

    }

    self.value = value

  }

}
