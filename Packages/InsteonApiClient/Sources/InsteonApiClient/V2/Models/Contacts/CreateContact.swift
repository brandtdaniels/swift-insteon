public struct CreateContact {

  public var name: String

  public var type: ContactType

  public var notify: String

  public var preferred: Bool

  public init(name: String, type: ContactType, notify: String, preferred: Bool) {

    self.name = name

    self.type = type

    self.notify = notify

    self.preferred = preferred

  }

}

// MARK: - Equatable

extension CreateContact: Equatable {}

// MARK: - Encodable

extension CreateContact: Encodable {

  private enum CodingKeys: String, CodingKey {

    case name = "ContactName"

    case type = "ContactType"

    case notify = "NotifyTo"

    case preferred = "Preferred"

  }

}
