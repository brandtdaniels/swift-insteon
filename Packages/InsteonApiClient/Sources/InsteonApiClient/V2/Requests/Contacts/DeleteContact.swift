import Foundation

public struct DeleteContact: ResponselessRequestProtocol {

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.contact(contactId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"

    return request

  }

  private let contactId: Int

  public init(contactId: Int) {

    self.contactId = contactId

  }

}
