import Foundation

public struct GetContact: RequestProtocol {

  public typealias Response = Contact

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.contact(contactId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let contactId: Int

  public init(contactId: Int) {

    self.contactId = contactId

  }

}
