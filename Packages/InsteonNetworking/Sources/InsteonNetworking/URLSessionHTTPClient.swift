import Foundation

/// Adapts `URLSession` to `HTTPClient`.
public final class URLSessionHTTPClient {

  private let session: URLSession

  public init(session: URLSession = .shared) {

    self.session = session

  }

}

// MARK: - HTTPClient

extension URLSessionHTTPClient: HTTPClient {

  public func send(
    _ request: URLRequest,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  ) {

    let task = session.dataTask(with: request) { data, response, error in

      if let error = error {

        completion(.failure(error))

        return

      }

      guard let response = response as? HTTPURLResponse else {

        completion(.failure(HTTPClientError.nonHTTPResponse))

        return

      }

      completion(.success(HTTPResponse(data: data ?? Data(), response: response)))

    }

    task.resume()

  }

}
