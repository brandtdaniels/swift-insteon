public struct CreateContactList {

  public var contacts: [CreateContact]

}

// MARK: - Encodable

extension CreateContactList: Encodable {

  private enum CodingKeys: String, CodingKey {

    case contacts = "ContactList"

  }

}
