import Foundation

public struct GetScenes: RequestProtocol {

  public typealias Response = SceneList

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.houseScenes(houseId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let houseId: Int

  public init(houseId: Int) {

    self.houseId = houseId

  }

}
