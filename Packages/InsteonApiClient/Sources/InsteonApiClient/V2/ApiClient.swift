import Foundation
import InsteonNetworking

public final class ApiClient {

  private let httpClient: HTTPClient

  private let decoder: ResponseDecoder

  /// Sends requests through `httpClient` unchanged, so it is responsible for authenticating them.
  public init(
    httpClient: HTTPClient,
    decoder: ResponseDecoder = InsteonResponseDecoder()
  ) {

    self.httpClient = httpClient
    self.decoder = decoder

  }

  /// Authenticates every request with `apiKey` and a token from `tokenProvider`.
  public convenience init(
    apiKey: String,
    tokenProvider: AccessTokenProvider,
    httpClient: HTTPClient = URLSessionHTTPClient()
  ) {

    self.init(
      httpClient: AuthenticatingHTTPClient(
        httpClient,
        apiKey: apiKey,
        tokenProvider: tokenProvider
      )
    )

  }

  private func perform<Value>(
    _ urlRequest: URLRequest,
    completion: @escaping ResultCallback<Value>,
    transform: @escaping (HTTPResponse) throws -> Value
  ) {

    let decoder = self.decoder

    httpClient.send(urlRequest) { result in

      switch result {

      case let .failure(error):

        completion(.failure(.request(message: error.localizedDescription)))

      case let .success(response) where response.isSuccess:

        do {

          completion(.success(try transform(response)))

        } catch {

          completion(.failure(.decoding(message: error.localizedDescription)))

        }

      case let .success(response):

        if let errorResponse = try? decoder.decode(ErrorResponse.self, from: response.data) {

          completion(.failure(.server(code: errorResponse.code, message: errorResponse.message)))

        } else {

          completion(.failure(.unknown(message: "Unexpected status code \(response.statusCode)")))

        }

      }

    }

  }

}

// MARK: - ApiClientProtocol

extension ApiClient: ApiClientProtocol {

  public func request<T: RequestProtocol>(_ request: T, completion: @escaping ResultCallback<T.Response>) {

    let decoder = self.decoder

    perform(request.urlRequest, completion: completion) { response in

      try decoder.decode(T.Response.self, from: response.data)

    }

  }

  public func request<T: ResponselessRequestProtocol>(_ request: T, completion: @escaping ResultCallback<Void>) {

    perform(request.urlRequest, completion: completion) { _ in () }

  }

}
