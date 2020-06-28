import Foundation

public struct GetCameras: RequestProtocol {

  public typealias Response = CameraList

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.houseCameras(houseId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let houseId: Int

  public init(houseId: Int) {

    self.houseId = houseId

  }

}
