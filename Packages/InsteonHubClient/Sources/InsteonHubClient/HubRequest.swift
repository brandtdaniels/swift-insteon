import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonProtocol

/// The requests the Hub's local HTTP interface accepts.
enum HubRequest {

  /// Passes a serial command to the Hub's modem.
  case send(SerialCommand)

  /// Reads the buffer of bytes the modem has sent back.
  case readBuffer

  /// Clears the buffer.
  case clearBuffer

  var path: String {

    switch self {
    case .send: "/3"
    case .readBuffer: "/buffstatus.xml"
    case .clearBuffer: "/1"
    }

  }

  /// The query, already percent-encoded. The Hub expects the command's hex where a query name
  /// would go.
  var query: String? {

    switch self {
    case let .send(command): "\(command.hexString)=I=3"
    case .readBuffer: nil
    case .clearBuffer: "XB=M=1"
    }

  }

  /// The request, a GET for every action. It always goes to the Hub rather than a cache, since
  /// the buffer changes between reads.
  func urlRequest(for endpoint: HubEndpoint) throws(HubError) -> URLRequest {

    // Components set the host as a host, so it can't change the request's path or authority.
    var components = URLComponents()
    components.scheme = "http"
    components.host = endpoint.host
    components.port = endpoint.port
    components.path = path
    components.percentEncodedQuery = query

    guard !endpoint.host.isEmpty, let url = components.url, url.host != nil else {

      throw .invalidEndpoint(endpoint)

    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    return request

  }

}
