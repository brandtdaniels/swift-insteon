public struct ErrorResponse {

  /// The code the API returns when it rejects the access token.
  static let invalidAccessKeyCode = 4014

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
