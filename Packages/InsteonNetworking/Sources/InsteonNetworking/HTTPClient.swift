import Foundation

/// The single seam through which every Insteon client talks to the network.
///
/// Conform any transport to this protocol (URLSession, Alamofire, a mock) and
/// pass it to `HubClient` or `ApiClient`.
public protocol HTTPClient {

  func send(
    _ request: URLRequest,
    completion: @escaping (Result<HTTPResponse, Error>) -> Void
  )

}
