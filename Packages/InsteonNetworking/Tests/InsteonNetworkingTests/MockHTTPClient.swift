import Foundation
import InsteonNetworking

final class MockHTTPClient: HTTPClient {

  private(set) var requests: [URLRequest] = []

  private let result: Result<HTTPResponse, Error>

  init(result: Result<HTTPResponse, Error>) {

    self.result = result

  }

  func send(
    _ request: URLRequest,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  ) {

    requests.append(request)

    completion(result)

  }

}
