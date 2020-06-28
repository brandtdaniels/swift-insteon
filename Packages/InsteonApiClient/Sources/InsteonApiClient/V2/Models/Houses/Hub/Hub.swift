public struct Hub {

    public var insteonIdentifier: String

    public var macAddress: String

    public var ipAddress: String

    public var port: Int

    public var gatewayAddress: String

    public var subnetMask: String

    public var city: String

    public var isDhcpSet: Bool

    public var isDaylightSavingsSet: Bool

    public var username: String

    public var password: String

    public var type: HubType

    public var binVersion: String

    public var plmVersion: String

    public var firmwareVersion: String

    public var isReachable: Bool?

}

// MARK: - Decodable

extension Hub: Decodable {

  private enum CodingKeys: String, CodingKey {

      case insteonIdentifier = "InsteonHubID"

      case macAddress = "Mac"

      case ipAddress = "IP"

      case port = "Port"

      case gatewayAddress = "Gateway"

      case subnetMask = "Mask"

      case city = "City"

      case isDhcpSet = "DHCP"

      case isDaylightSavingsSet = "DaylightSavings"

      case username = "HubUsername"

      case password = "HubPassword"

      case type = "HubType"

      case isReachable = "HubReachable"

      case binVersion = "BinVer"

      case plmVersion = "PLMVer"

      case firmwareVersion = "FirmwareVer"

  }

  public init(from decoder: Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)

      insteonIdentifier = try container.decode(String.self, forKey: .insteonIdentifier)

      macAddress = try container.decode(String.self, forKey: .macAddress)

      ipAddress = try container.decode(String.self, forKey: .ipAddress)

      if let portStr = try? container.decode(String.self, forKey: .port) {
          port = Int(portStr)!
      } else {
          port = 0
      }

      gatewayAddress = try container.decode(String.self, forKey: .gatewayAddress)

      subnetMask = try container.decode(String.self, forKey: .subnetMask)

      city = try container.decode(String.self, forKey: .city)

      if let dhcp = try? container.decode(String.self, forKey: .isDhcpSet) {
          isDhcpSet = dhcp.lowercased() == "true" ? true : false
      } else {
          isDhcpSet = false
      }

      if let daylightSavings = try? container.decode(String.self, forKey: .isDaylightSavingsSet) {
          isDaylightSavingsSet = daylightSavings.lowercased() == "true" ? true : false
      } else {
          isDaylightSavingsSet = false
      }

      username = try container.decode(String.self, forKey: .username)

      password = try container.decode(String.self, forKey: .password)

      type = try container.decode(HubType.self, forKey: .type)

      binVersion = try container.decode(String.self, forKey: .binVersion)

      plmVersion = try container.decode(String.self, forKey: .plmVersion)

      firmwareVersion = try container.decode(String.self, forKey: .firmwareVersion)

      isReachable = try container.decodeIfPresent(Bool.self, forKey: .isReachable)

  }

}

// MARK: - Equatable

extension Hub: Equatable {

    public static func ==(rhs: Hub, lhs: Hub) -> Bool {

        return rhs.macAddress == lhs.macAddress

    }

}
