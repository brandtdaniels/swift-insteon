import Foundation

/// Decorates an `HTTPClient` by adding an HTTP basic `Authorization` header to every request.
public struct BasicAuthenticationHTTPClient {

  private let httpClient: HTTPClient

  private let user: String

  private let password: String

  public init(_ httpClient: HTTPClient, user: String, password: String) {

    self.httpClient = httpClient
    self.user = user
    self.password = password

  }

}

// MARK: - HTTPClient

extension BasicAuthenticationHTTPClient: HTTPClient {

  public func send(
    _ request: URLRequest,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  ) {

    let credentials = Data("\(user):\(password)".utf8).base64EncodedString()

    var request = request
    request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

    httpClient.send(request, completion: completion)

  }

}
