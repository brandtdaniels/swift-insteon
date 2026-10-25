public struct DeviceList {

  public var devices: [Device]

}

// MARK: - Decodable

extension DeviceList: Decodable {

  private enum CodingKeys: String, CodingKey {

    case devices = "DeviceList"

  }

}
