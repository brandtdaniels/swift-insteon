public struct ErrorResponse {

  public var message: String

  public var code: Int

}

// MARK: - Decodable

extension ErrorResponse: Decodable {

  private enum CodingKeys: String, CodingKey {

    case message

    case code

  }

}
