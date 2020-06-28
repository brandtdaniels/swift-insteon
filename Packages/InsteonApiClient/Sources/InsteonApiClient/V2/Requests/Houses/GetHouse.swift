import Foundation

public struct GetHouse: RequestProtocol {

  public typealias Response = House

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.house(houseId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let houseId: Int

  public init(_ houseId: Int) {

    self.houseId = houseId

  }

}
