import Foundation

public struct DeleteRoom: ResponselessRequestProtocol {

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.room(roomId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"

    return request

  }

  private let roomId: Int

  public init(roomId: Int) {

    self.roomId = roomId

  }

}
