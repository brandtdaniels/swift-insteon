import Foundation

public struct HTTPResponse {

  public let data: Data

  public let response: HTTPURLResponse

  public var statusCode: Int {

    return response.statusCode

  }

  public var isSuccess: Bool {

    return (200...299).contains(statusCode)

  }

  public init(data: Data, response: HTTPURLResponse) {

    self.data = data
    self.response = response

  }

}
