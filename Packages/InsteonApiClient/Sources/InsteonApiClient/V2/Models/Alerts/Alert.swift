public struct Alert {

  public var houseIdentifier: Int

  public var deviceIdentifier: Int

  public var identifier: Int

  public var name: String

  public var subject: String

  public var body: String

  public var deviceState: DeviceState

  public var contacts: [ContactId]

}

// MARK: -

extension Alert: Equatable {}

// MARK: - Codable

extension Alert: Codable {

  private enum CodingKeys: String, CodingKey {

    case houseIdentifier = "HouseID"

    case deviceIdentifier = "DeviceID"

    case identifier = "AlertID"

    case name = "AlertName"

    case subject = "AlertSubject"

    case body = "AlertBody"

    case deviceState = "DeviceState"

    case contacts = "ContactList"

  }

  public init(from decoder: Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    identifier = try container.decode(Int.self, forKey: .identifier)

    name = try container.decode(String.self, forKey: .name)

    houseIdentifier = try container.decode(Int.self, forKey: .houseIdentifier)

    subject = try container.decode(String.self, forKey: .subject)

    body = try container.decode(String.self, forKey: .body)

    deviceIdentifier = try container.decode(Int.self, forKey: .deviceIdentifier)

    let deviceStateStr = try container.decode(String.self, forKey: .deviceState)

    deviceState = DeviceState(rawValue: deviceStateStr)

    contacts = try container.decode([ContactId].self, forKey: .contacts)

  }

  public func encode(to encoder: Encoder) throws {

    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(identifier, forKey: .identifier)

    try container.encode(name, forKey: .name)

    try container.encode(houseIdentifier, forKey: .houseIdentifier)

    try container.encode(subject, forKey: .subject)

    try container.encode(body, forKey: .body)

    try container.encode(deviceIdentifier, forKey: .deviceIdentifier)

    try container.encode(deviceState.rawValue, forKey: .deviceState)

    try container.encode(contacts, forKey: .contacts)

  }

}
