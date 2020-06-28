public struct ContactId {

  public var identifier: Int

  public init(_ identifier: Int) {

    self.identifier = identifier

  }

}

// MARK: - Equatable

extension ContactId: Equatable {}

// MARK: - Codable

extension ContactId: Codable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "ContactID"

  }

}
