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

  /// Reads a page of a 2242 Hub's slot statuses.
  case readSlots(page: Int)

  /// Writes a 2242 Hub slot's timer, with the fields already joined.
  case writeTimer(HubSlot, fields: String)

  /// Writes the commands a 2242 Hub slot's timer sends, or clears them.
  case writeCommands(HubSlot, HubSlotCommands?)

  /// Sets a 2242 Hub's clock.
  case setTime(HubClockTime)

  /// Sets a 2242 Hub's day of the week.
  case setWeekday(HubWeekday)

  var path: String {

    switch self {
    case .write: "/3"
    case .readBuffer: "/buffstatus.xml"
    case .clearBuffer, .setWeekday: "/1"
    case .readSlots: "/b.xml"
    case .writeTimer, .writeCommands: "/2"
    case .setTime: "/hnetwork.htm"
    }

  }

  /// The query, already percent-encoded. The Hub expects the bytes as hex where a query name
  /// would go.
  var query: String? {

    switch self {
    case let .write(bytes): "\(Self.hex(bytes))=I=3"
    case .readBuffer: nil
    case .clearBuffer: "XB=M=1"
    case let .readSlots(page): "01=\(page < 10 ? "0" : "")\(page)=F"
    case let .writeTimer(slot, fields): "S\(slot.rawValue)=\(fields)"
    case let .writeCommands(slot, commands?): "C\(slot.rawValue)=\(Self.hex(commands.on.bytes))=2tt\(Self.hex(commands.off.bytes))"
    case let .writeCommands(slot, nil): "C\(slot.rawValue)=-=2ff-"
    // The fields after the time are what Insteon's Hub app sends; it doesn't say what they mean.
    case let .setTime(time): "TD=\(time.clockText)=1=falsefalse"
    case let .setWeekday(day): "D=1=1=" + HubWeekday.allCases.map { $0 == day ? "t=" : "f=" }.joined()
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
