import Foundation

public struct UpdateRoom: ResponselessRequestProtocol {

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.room(roomId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = roomData

    return request

  }

  private let roomId: Int
  private let roomData: Data

  public init(roomId: Int, roomData: Data) {

    self.roomId = roomId
    self.roomData = roomData

  }

}
