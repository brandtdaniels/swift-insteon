public struct Device {

  public var houseIdentifier: Int

  public var identifier: Int

  public var name: String

  public var iconIdentifier: Int

  public var insteonIdentifier: String

  public var category: DeviceCategory

  public var subCategory: Int

  public var groupCount: Int

  public var firmware: Int

  public var engine: DeviceEngine

  public var traits: DeviceTraits

  public var groups: [DeviceGroup]

}

// MARK: - Decodable

extension Device: Decodable {

  private enum CodingKeys: String, CodingKey {

    case houseIdentifier = "HouseID"

    case identifier = "DeviceID"

    case name = "DeviceName"

    case iconIdentifier = "IconID"

    case insteonIdentifier = "InsteonID"

    case category = "DevCat"

    case subCategory = "SubCat"

    case groupCount = "ConfiguredGroups"

    case firmware = "FirmwareVersion"

    case engine = "InsteonEngine"

    case traits = "DeviceTypeTraits"

    case groups = "GroupList"

  }

}

// MARK: - Equatable

extension Device: Equatable {

  public static func ==(lhs: Device, rhs: Device) -> Bool {

    return lhs.identifier == rhs.identifier

  }

}
