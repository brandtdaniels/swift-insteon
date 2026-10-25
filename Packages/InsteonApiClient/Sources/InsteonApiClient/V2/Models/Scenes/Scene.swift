public struct Scene {

  public var houseIdentifier: Int

  public var identifier: Int

  public var name: String

  public var devices: [SceneDeviceGroup]

}

// MARK: - Decodable

extension Scene: Decodable {

  private enum CodingKeys: String, CodingKey {

    case houseIdentifier = "HouseID"

    case identifier = "SceneID"

    case name = "SceneName"

    case devices = "DeviceList"

  }

}

// MARK: - Equatable

extension Scene: Equatable {

  public static func ==(lhs: Scene, rhs: Scene) -> Bool {

    return lhs.identifier == rhs.identifier

  }

}
