import Foundation

public struct CreateContacts: RequestProtocol {

  public typealias Response = CreateContactListResponse

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.contacts).url!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = contactsData

    return request

  }

  private let contactsData: Data

  public init(_ contactsData: Data) {

    self.contactsData = contactsData

  }

}
