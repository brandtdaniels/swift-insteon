import Foundation

public struct Camera {

  public var houseIdentifier: Int

  public var identifier: Int

  public var name: String

  public var iconIdentifier: Int

  public var favorite: Bool

  public var username: String

  public var password: String

  public var model: Int

  public var serialNumber: String

  public var url: URL?

  public var manufacturer: String

  public var productType: String //TODO: Convert to enum type

  public var streamType: String //TODO: Convert to enum type

  public var macAddress: String

  public var systemVersion: String

  public var appVersion: String

  public var isDhcpEnabled: String //TODO: Convert to bool

  public var shouldUseP2p: String //TODO: Convert to bool

  public var p2pPort: String? //TODO: Convert to Int

  public var isP2pEnabled: String? //TODO: Convert to bool

  public var isP2pSupported: String? //TODO: Convert to bool


}

// MARK: - Decodable

extension Camera: Decodable {

  private enum CodingKeys: String, CodingKey {

    case houseIdentifier = "HouseID"

    case identifier = "CameraID"

    case name = "CameraName"

    case iconIdentifier = "IconID"

    case favorite = "Favorite"

    case username = "Username"

    case password = "Password"

    case model = "Model"

    case serialNumber = "SerialNumber"

    case url = "Url"

    case manufacturer = "Manufacturer"

    case productType = "ProductType"

    case streamType

    case macAddress

    case systemVersion

    case appVersion

    case isDhcpEnabled = "dhcpEnabled"

    case shouldUseP2p = "UseP2P"

    case p2pPort

    case isP2pEnabled = "p2pEnabled"

    case isP2pSupported = "p2pSupported"

  }

}

// MARK: - Equatable

extension Camera: Equatable {

  public static func ==(lhs: Camera, rhs: Camera) -> Bool {

    return lhs.identifier == rhs.identifier

  }

}
