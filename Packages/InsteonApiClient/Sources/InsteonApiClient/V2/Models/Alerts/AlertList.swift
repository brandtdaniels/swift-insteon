public struct AlertList {

  public var alerts: [Alert]

}

// MARK: - Decodable

extension AlertList: Decodable {

  private enum CodingKeys: String, CodingKey {

    case alerts = "AlertList"

  }

}
