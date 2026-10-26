import Foundation

public protocol ResponseDecoder {

  func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T

}

public struct InsteonResponseDecoder {

  private let decoder: JSONDecoder

  public init(decoder: JSONDecoder = JSONDecoder()) {

    self.decoder = decoder

  }

}

// MARK: - ResponseDecoder

extension InsteonResponseDecoder: ResponseDecoder {

  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {

    // The API returns raw newlines inside its JSON, which JSONDecoder rejects.
    let cleanData = Data(
      String(decoding: data, as: UTF8.self)
        .replacingOccurrences(of: "\n", with: "")
        .utf8
    )

    return try decoder.decode(type, from: cleanData)

  }

}
