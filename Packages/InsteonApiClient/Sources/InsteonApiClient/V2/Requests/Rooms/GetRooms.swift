import Foundation

public struct GetRooms: RequestProtocol {

  public typealias Response = RoomList

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.houseRooms(houseId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let houseId: Int

  public init(houseId: Int) {

    self.houseId = houseId
    
  }

}
