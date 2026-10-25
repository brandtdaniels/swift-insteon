import AuthClient
import Foundation
import RequestClient

public class ApiClient {

  private var tokenResponse: TokenResponse?

  private let requestClient: RequestClientProtocol

  private let authClient: AuthClientProtocol

  private let keychain: Keychain?

  public init(
    _ requestClient: RequestClientProtocol,
    _ authClient: AuthClientProtocol,
    _ keychain: Keychain? = nil) {

    self.requestClient = requestClient
    self.authClient = authClient
    self.keychain = keychain

    if let keychain = self.keychain,
      let accessToken = keychain.getString(key: "accessToken"),
      let refreshToken = keychain.getString(key: "refreshToken"),
      let tokenTypeStr = keychain.getString(key: "tokenType"),
      let tokenType = TokenType(rawValue: tokenTypeStr),
      let expiresIn =  keychain.getDouble(key: "expiresIn"),
      let _ = keychain.getString(key: "expirationDate")
    {

      tokenResponse = TokenResponse(
        accessToken: accessToken,
        refreshToken: refreshToken,
        tokenType: tokenType,
        expiresIn: expiresIn
      )

    }

  }

  private func authorize(completion: @escaping (Error?) -> Void) {

    authClient.authorize { [weak self] result in

      guard let self = self else {

        completion(ApiClientError.unknown(message: "Unknown error"))

        return

      }

      switch result {

      case let .failure(authError):

        completion(authError)

      case let .success(tokenResponse):

        if let keychain = self.keychain,
          let expirationDate = tokenResponse.expirationDateString {

          keychain.set(tokenResponse.accessToken, key: "accessToken")
          keychain.set(tokenResponse.refreshToken, key: "refreshToken")
          keychain.set(tokenResponse.tokenType.rawValue, key: "tokenType")
          keychain.set(tokenResponse.expiresIn, key: "expiresIn")
          keychain.set(expirationDate, key: "expirationDate")

        }

        self.tokenResponse = tokenResponse

        completion(nil)

      }

    }

  }

}

// MARK: - ApiClientProtocol

extension ApiClient: ApiClientProtocol {

  public func request<T: ResponselessRequestProtocol>(_ request: T, completion: @escaping ResultCallback<Void>) {

    guard let tokenResponse = tokenResponse,
      tokenResponse.isExpired == false else {

        authorize { error in

          guard error == nil else {

            completion(.failure(.unknown(message: "Unknown error")))

            return

          }

          DispatchQueue.main.async {

            self.request(request, completion: completion)

          }

        }

        return

    }

    requestClient.send(request.urlRequest) { [weak self] data, response, error in

      guard let self = self else {

        return

      }

      if let error = error {

        completion(.failure(.request(message: error.localizedDescription)))

      } else if let data = data,
        let response = response as? HTTPURLResponse {

        print("Response status code: \(response.statusCode)")

        if response.statusCode == 204 { // No Content

          completion(.success(()))

        } else {

          do {

            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)

            if errorResponse.code == 4014 { // Invalid access key

              self.tokenResponse = nil

              DispatchQueue.main.async {

                self.request(request, completion: completion)

              }

              return

            }

            completion(.failure(.server(code: errorResponse.code, message: errorResponse.message)))

          } catch (let error) {

            print(error)

            completion(.failure(.decoding(message: error.localizedDescription)))

          }

        }

      } else {

        completion(.failure(.unknown(message: "Unknown error")))

      }

    }

  }

  public func request<T: RequestProtocol>(_ request: T, completion: @escaping ResultCallback<T.Response>) {

    if tokenResponse == nil ||
      tokenResponse?.isExpired == true {

        authorize { error in

          guard error == nil else {

            completion(.failure(.unknown(message: "Unknown error")))

            return

          }

          DispatchQueue.main.async {

            self.request(request, completion: completion)

          }

        }

      return

    }

//    requestClient.addHeaders([
//      "Authentication": "APIKey \(authorizer.clientId)",
//      "Authorization": "Bearer \(tokenResponse.accessToken)"
//    ])

    requestClient.send(request.urlRequest) { [weak self] data, response, error in

      guard let self = self else {

        return

      }

      if let error = error {

        completion(.failure(.request(message: error.localizedDescription)))

      } else if let data = data,
        let response = response as? HTTPURLResponse {

        print("Response status code: \(response.statusCode)")

        if response.statusCode == 200 // OK
          || response.statusCode == 201 // Created
          || response.statusCode == 202, // Accepted
          let dataStr = String(data: data, encoding: .utf8),
          let cleanData = dataStr.replacingOccurrences(of: "\n", with: "", options: .regularExpression)
            .data(using: .utf8) {

          do {

            let decodable = try JSONDecoder().decode(T.Response.self, from: cleanData)

            completion(.success(decodable))

          } catch (let error) {

            print(error)

            completion(.failure(.decoding(message: error.localizedDescription)))

          }

        } else {

          do {

            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)

            if errorResponse.code == 4014 { // Invalid access key

              self.tokenResponse = nil

              DispatchQueue.main.async {

                self.request(request, completion: completion)

              }

              return

            }

            completion(.failure(.server(code: errorResponse.code, message: errorResponse.message)))

          } catch (let error) {

            print(error)

            completion(.failure(.decoding(message: error.localizedDescription)))

          }

        }

      } else {

        completion(.failure(.unknown(message: "Unknown error")))

      }

    }

  }

}
