import Foundation

public struct GetAlerts: RequestProtocol {

  public typealias Response = AlertList

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.houseAlerts(houseId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let houseId: Int

  public init(houseId: Int) {

    self.houseId = houseId

  }

}
