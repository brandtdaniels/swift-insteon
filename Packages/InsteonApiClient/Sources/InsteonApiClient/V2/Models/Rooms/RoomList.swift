public struct RoomList {

  public var rooms: [Room]

}

// MARK: - Decodable

extension RoomList: Decodable {

  private enum CodingKeys: String, CodingKey {

    case rooms = "RoomList"

  }

}
