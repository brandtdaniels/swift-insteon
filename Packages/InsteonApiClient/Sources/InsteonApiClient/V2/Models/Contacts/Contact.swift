public struct Contact {

  public var identifier: Int

  public var name: String

  public var type: ContactType

  public var notify: String

  public var preferred: Bool

  public var approved: Bool

}

// MARK: - Equatable

extension Contact: Equatable {}

// MARK: - Decodable

extension Contact: Decodable {

  private enum CodingKeys: String, CodingKey {

    case identifier = "ContactID"

    case name = "ContactName"

    case type = "ContactType"

    case notify = "NotifyTo"

    case preferred = "Preferred"

    case approved = "Approved"

  }

  public init(from decoder: Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    identifier = try container.decode(Int.self, forKey: .identifier)

    name = try container.decode(String.self, forKey: .name)

    notify = try container.decode(String.self, forKey: .notify)

    preferred = try container.decode(Bool.self, forKey: .preferred)

    approved = try container.decode(Bool.self, forKey: .approved)

    var rawType = try container.decode(String.self, forKey: .type)

    // This is due to a bug in ContactType being empty
    // when fetching PNS type contact using GET /contacts/{id}
    if rawType == "", notify == "Push Notification" {

      rawType = "PNS"

    }

    type = ContactType(rawValue: rawType) ?? .email

  }

}
