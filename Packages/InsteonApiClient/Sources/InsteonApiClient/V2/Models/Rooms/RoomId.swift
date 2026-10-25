public struct RoomId {

  public var identifier: Int

  public init(_ identifier: Int) {

    self.identifier = identifier

  }

}

// MARK: - Equatable

extension RoomId: Equatable {}

// MARK: - Codable

extension RoomId: Codable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "RoomID"

  }

}
