public struct House {
    
    public var identifier: Int
    
    public var name: String
    
    public var iconIdentifier: Int
    
    public var hub: Hub?

}

// MARK: - Decodable

extension House: Decodable {

  private enum CodingKeys: String, CodingKey {

      case identifier = "HouseID"

      case name = "HouseName"

      case iconIdentifier = "IconID"

      case hub

  }

  public init(from decoder: Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)

      identifier = try container.decode(Int.self, forKey: .identifier)

      name = try container.decode(String.self, forKey: .name)

      iconIdentifier = try container.decode(Int.self, forKey: .iconIdentifier)

      if let hub = try? Hub(from: decoder) {

          self.hub = hub

      }

  }

}

// MARK: - Equatable

extension House: Equatable {

    public static func ==(lhs: House, rhs: House) -> Bool {

        return lhs.identifier == rhs.identifier

    }

}
