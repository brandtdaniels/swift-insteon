import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonProtocol

/// The requests the Hub's local HTTP interface accepts. Package-wide, so Hub discovery asks for
/// the buffer page exactly as ``Hub`` does.
package enum HubRequest {

  /// Passes bytes to the Hub's modem.
  case write([UInt8])

  /// Reads the buffer of bytes the modem has sent back.
  case readBuffer

  /// Clears the buffer.
  case clearBuffer

  var path: String {

    switch self {
    case .write: "/3"
    case .readBuffer: "/buffstatus.xml"
    case .clearBuffer: "/1"
    }

  }

  /// The query, already percent-encoded. The Hub expects the bytes as hex where a query name
  /// would go.
  var query: String? {

    switch self {
    case let .write(bytes): "\(Self.hex(bytes))=I=3"
    case .readBuffer: nil
    case .clearBuffer: "XB=M=1"
    }

  }

  /// Uppercase hex, two digits per byte.
  private static func hex(_ bytes: [UInt8]) -> String {

    bytes.map(\.hexDigits).joined()

  }

  /// The request, a GET for every action. It always goes to the Hub rather than a cache, since
  /// the buffer changes between reads.
  package func urlRequest(for endpoint: HubEndpoint) throws(HubError) -> URLRequest {

    // URLComponents traps on a negative port, so an out-of-range port is rejected first.
    guard (0...65_535).contains(endpoint.port) else {

      throw .invalidEndpoint(endpoint)

    }

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
