public struct DeviceGroup {

  public var sceneIdentifier: Int

  public var identifier: Int

  public var number: Int

  public var name: String

  public var state: Int

  public init(sceneIdentifier: Int, identifier: Int, number: Int, name: String, state: Int) {

    self.sceneIdentifier = sceneIdentifier

    self.identifier = identifier

    self.number = number

    self.name = name

    self.state = state

  }

}

// MARK: - Decodable

extension DeviceGroup: Decodable {

  private enum CodingKeys: String, CodingKey {
    
    case sceneIdentifier = "SceneID"

    case identifier = "DeviceGroupDetailID"

    case number = "GroupNum"

    case name = "GroupName"

    case state = "GroupState"

  }

}
