public struct CreateContactListResponse {

  public var contacts: [ContactId]

}

// MARK: - Decodable

extension CreateContactListResponse: Decodable {

  private enum CodingKeys: String, CodingKey {

    case contacts = "ContactList"

  }

}
