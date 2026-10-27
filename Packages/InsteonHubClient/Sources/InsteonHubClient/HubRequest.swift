import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
/// The requests the Hub's local HTTP interface accepts.
enum HubRequest {

  /// Passes bytes to the Hub's modem.
  case write([UInt8])

  /// Reads the buffer of bytes the modem has sent back.
  case readBuffer

  /// Clears the buffer.
  case clearBuffer

  var method: String {

    switch self {
    case .write, .clearBuffer: "POST"
    case .readBuffer: "GET"
    }

  }

  /// The path and query. The Hub expects the bytes as hex where a query name would go.
  var pathAndQuery: String {

    switch self {
    case let .write(bytes): "/3?\(Self.hex(bytes))=I=3"
    case .readBuffer: "/buffstatus.xml"
    case .clearBuffer: "/1?XB=M=1"
    }

  }

  /// Uppercase hex, two digits per byte.
  private static func hex(_ bytes: [UInt8]) -> String {

    bytes.map { $0 < 0x10 ? "0" + String($0, radix: 16, uppercase: true) : String($0, radix: 16, uppercase: true) }.joined()

  }

  func urlRequest(for endpoint: HubEndpoint) throws(HubError) -> URLRequest {

    guard let url = URL(string: "http://\(endpoint.host):\(endpoint.port)\(pathAndQuery)") else {

      throw .invalidEndpoint(endpoint)

    }

    var request = URLRequest(url: url)
    request.httpMethod = method

    return request

  }

}
