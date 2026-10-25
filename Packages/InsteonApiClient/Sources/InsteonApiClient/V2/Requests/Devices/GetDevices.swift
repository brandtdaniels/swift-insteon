import Foundation

public struct GetDevices: RequestProtocol {

  public typealias Response = DeviceList

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.houseDevices(houseId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let houseId: Int

  public init(houseId: Int) {

    self.houseId = houseId

  }

}
