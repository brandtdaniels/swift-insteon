public struct Room {

  public var houseIdentifier: Int

  public var identifier: Int

  public var name: String

  public var iconIdentifier: Int

  public var isFavorite: Bool

  public var isVisible: Bool

  public var defaultCameraIdentifier: Int

  public var devices: [DeviceId]

  public var cameras: [CameraId]

  public var scenes: [SceneId]

  public init(houseId: Int, name: String) {

    houseIdentifier = houseId

    self.name = name

    identifier = 0
    iconIdentifier = 0
    defaultCameraIdentifier = 0

    isFavorite = true
    isVisible = true

    devices = []
    cameras = []
    scenes = []

  }

}

// MARK: - Codable

extension Room: Codable {

  private enum CodingKeys: String, CodingKey {

    case houseIdentifier = "HouseID"

    case identifier = "RoomID"

    case name = "RoomName"

    case iconIdentifier = "IconID"

    case isFavorite = "Favorite"

    case isVisible = "Visible"

    case defaultCameraIdentifier = "DefaultCamera"

    case devices = "DeviceList"

    case cameras = "CameraList"

    case scenes = "SceneList"

  }

}
