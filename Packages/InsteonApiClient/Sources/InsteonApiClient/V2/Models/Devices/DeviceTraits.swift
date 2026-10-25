public struct DeviceTraits {

  public var isSecurityDevice: Bool

  public var description: String

}

// MARK: - Decodable

extension DeviceTraits: Decodable {

  private enum CodingKeys: String, CodingKey {

    case isSecurityDevice = "SecurityDevice"

    case description = "TypeDescription"

  }

}
