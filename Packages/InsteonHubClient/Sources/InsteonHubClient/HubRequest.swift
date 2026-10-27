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

  var method: String {

    switch self {
    case .send, .clearBuffer: "POST"
    case .readBuffer: "GET"
    }

  }

  /// The path and query. The Hub expects the command's hex where a query name would go.
  var pathAndQuery: String {

    switch self {
    case let .send(command): "/3?\(command.hexString)=I=3"
    case .readBuffer: "/buffstatus.xml"
    case .clearBuffer: "/1?XB=M=1"
    }

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
