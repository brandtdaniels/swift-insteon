import Foundation

public struct GetDevice: RequestProtocol {

  public typealias Response = Device

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.device(deviceId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let deviceId: Int

  public init(deviceId: Int) {

    self.deviceId = deviceId

  }

}
