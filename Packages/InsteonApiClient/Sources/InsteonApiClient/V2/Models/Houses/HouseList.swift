public struct HouseList {

  public var houses: [House]

}

// MARK: - Decodable

extension HouseList: Decodable {

  private enum CodingKeys: String, CodingKey {

    case houses = "HouseList"

  }

}
