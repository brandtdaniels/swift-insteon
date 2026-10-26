# InsteonNetworking

The networking abstraction shared by the Insteon clients.

* `HTTPClient` is the only networking dependency `HubClient` and `ApiClient` have. Conform any transport to it.
* `URLSessionHTTPClient` is the default implementation, an adapter over `URLSession`.
* `BasicAuthenticationHTTPClient` decorates any `HTTPClient` with HTTP basic authentication.

## Bringing your own transport

```swift
import Alamofire
import InsteonNetworking

struct AlamofireHTTPClient: HTTPClient {

  func send(_ request: URLRequest, completion: @escaping (Result<HTTPResponse, Error>) -> Void) {

    AF.request(request).responseData { response in

      switch (response.result, response.response) {
      case let (.success(data), httpResponse?):
        completion(.success(HTTPResponse(data: data, response: httpResponse)))
      case let (.failure(error), _):
        completion(.failure(error))
      default:
        completion(.failure(HTTPClientError.nonHTTPResponse))
      }

    }

  }

}
```
