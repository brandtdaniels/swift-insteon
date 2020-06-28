import Foundation

public struct UpdateAlert: ResponselessRequestProtocol {

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.alert(alertId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = alertData

    return request

  }

  private let alertId: Int
  private let alertData: Data

  public init(_ alertId: Int, _ alertData: Data) {

    self.alertId = alertId
    self.alertData = alertData

  }

}
