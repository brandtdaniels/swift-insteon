public struct SceneDeviceGroup {

  public var deviceIdentifier: Int

  public var identifier: Int

  public var onLevel: Int

  public var rampRate: Int

  public var sceneRole: SceneDeviceGroupRole

}

// MARK: - Decodable

extension SceneDeviceGroup: Decodable {

  private enum CodingKeys: String, CodingKey {

    case deviceIdentifier = "DeviceID"

    case identifier = "DeviceGroupDetailID"

    case onLevel = "OnLevel"

    case rampRate = "RampRate"

    case sceneRole = "DeviceRoleMask"

  }

}
