public struct ContactList {

  public var contacts: [Contact]

}

// MARK: - Decodable

extension ContactList: Decodable {

  private enum CodingKeys: String, CodingKey {

    case contacts = "ContactList"

  }

}
