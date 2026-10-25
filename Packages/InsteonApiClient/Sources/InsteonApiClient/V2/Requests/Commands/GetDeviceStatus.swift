import Foundation

public struct GetDeviceStatus: RequestProtocol {

  public typealias Response = StatusResponse

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.commands).url!

//    let json: [String : Any] = ["command": "get_status", "device_id": deviceId]
//
//    guard let jsonData = try?  JSONSerialization.data(withJSONObject: json) else {
//
//      return nil
//
//    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData

    return request

  }

  private let jsonData: Data

  public init(jsonData: Data) {

    self.jsonData = jsonData

  }

}
