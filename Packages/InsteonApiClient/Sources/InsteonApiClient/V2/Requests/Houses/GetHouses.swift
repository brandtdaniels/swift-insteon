import Foundation

public struct GetHouses: RequestProtocol {

  public typealias Response = HouseList

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.houses).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  public init() {}

}
