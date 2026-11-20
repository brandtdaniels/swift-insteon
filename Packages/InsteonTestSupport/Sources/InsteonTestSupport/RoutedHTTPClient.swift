import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking

/// Answers each request by its method, path and query, records what was sent, and can hold a
/// request until the test lets it go.
public actor RoutedHTTPClient: HTTPClient {

  /// Every request sent, as `METHOD path?query`, oldest first.
  public private(set) var sent: [String] = []

  private var routes: [String: HTTPResponse]
  private var holdsNext = false
  private var held: CheckedContinuation<Void, Never>?
  private var arrivals: [CheckedContinuation<Void, Never>] = []

  /// Creates a client.
  ///
  /// - Parameter routes: The answers by `METHOD path?query`. A request with no route gets 404.
  public init(_ routes: [String: HTTPResponse] = [:]) {

    self.routes = routes

  }

  public func answer(_ route: String, with response: HTTPResponse) {

    routes[route] = response

  }

  /// Holds the next request after it is recorded, until ``release()``.
  public func holdNextRequest() {

    holdsNext = true

  }

  /// Returns once at least `count` requests have been sent.
  public func waitForRequests(_ count: Int) async {

    while sent.count < count {

      await withCheckedContinuation { arrivals.append($0) }

    }

  }

  public func release() {

    held?.resume()
    held = nil

  }

  public func send(_ request: URLRequest) async throws -> HTTPResponse {

    var key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"

    if let query = request.url?.query {

      key += "?\(query)"

    }

    sent.append(key)

    let waiting = arrivals
    arrivals = []
    waiting.forEach { $0.resume() }

    if holdsNext {

      holdsNext = false

      await withCheckedContinuation { held = $0 }

    }

    return routes[key] ?? HTTPResponse(statusCode: 404)

  }

}

/// A JSON answer with status 200.
public func answerJSON(_ text: String, status: Int = 200) -> HTTPResponse {

  HTTPResponse(statusCode: status, body: Data(text.utf8))

}

/// What a Hub Pro with a lamp dimmer answers, with invented addresses.
public enum HubProUnit {

  public static let host = "192.0.2.10"

  public static let list = #"[{"location":"","name":"(PLM)","device":"AA.BB.CC","deviceType":"Hub Pro"},{"location":"","name":"Example Dimmer","device":"11.22.33","deviceType":"Example Dimmer"}]"#

  public static let status = #"[{"OnLevel":0,"device":"11.22.33"}]"#

  public static let describe = #"{"commands":[{"name":"Beep"},{"name":"On","parameters":["OnLevel"]},{"name":"Off"},{"name":"StatusRequest"},{"name":"WriteLink"},{"name":"ClearLink"}],"devCat":1,"device":"11.22.33","deviceType":"Example Dimmer","firmwareVersion":59,"links":{"delta":0,"pending":false,"records":[]},"location":"","name":"Example Dimmer","properties":{"LinkMemoryBaseAddress":4095,"LinkMemorySize":417},"removing":false,"sku":"9101X1","subCat":14}"#

  public static let statusRequest = #"{"LinkDelta":5,"OnLevel":0,"command":"StatusRequest","device":"11.22.33","result":"successful"}"#

  public static let succeeded = #"{"command":"On","device":"11.22.33","result":"successful"}"#

  public static let unknownDevice = #"{"command":"insteon/command","device":"00.00.00","error":"Key '00.00.00' not found.","key":"k"}"#

  public static let unsupportedKey = #"{"command":"insteon/command","device":"11.22.33","error":"Device 11.22.33 does not support command 'k'.","key":"k"}"#

  public static let missingParameters = #"{"command":"insteon/command","error":"The following required parameters were not specified: 'device, key'"}"#

}
