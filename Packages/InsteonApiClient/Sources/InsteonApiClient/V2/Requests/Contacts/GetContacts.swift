import Foundation

public struct GetContacts: RequestProtocol {

  public typealias Response = ContactList

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.contacts).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  public init() {}

}
