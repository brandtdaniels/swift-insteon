import Foundation

public struct CreateRoom: RequestProtocol {

  public typealias Response = RoomId

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.rooms).url!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = roomData

    return request

  }

  private let roomData: Data

  public init(_ roomData: Data) {

    self.roomData = roomData

  }

}
