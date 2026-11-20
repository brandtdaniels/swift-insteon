import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonNetworking

/// Answers each request by its method, path and query, records what was sent, and can hold a
/// request until the test lets it go.
actor RoutedHTTPClient: HTTPClient {

  /// Every request sent, as `METHOD path?query`, oldest first.
  private(set) var sent: [String] = []

  private var routes: [String: HTTPResponse]
  private var holdsNext = false
  private var held: CheckedContinuation<Void, Never>?
  private var arrivals: [CheckedContinuation<Void, Never>] = []

  /// Creates a client.
  ///
  /// - Parameter routes: The answers by `METHOD path?query`. A request with no route gets 404.
  init(_ routes: [String: HTTPResponse] = [:]) {

    self.routes = routes

  }

  func answer(_ route: String, with response: HTTPResponse) {

    routes[route] = response

  }

  /// Holds the next request after it is recorded, until ``release()``.
  func holdNextRequest() {

    holdsNext = true

  }

  /// Returns once at least `count` requests have been sent.
  func waitForRequests(_ count: Int) async {

    while sent.count < count {

      await withCheckedContinuation { arrivals.append($0) }

    }

  }

  func release() {

    held?.resume()
    held = nil

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

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
func json(_ text: String, status: Int = 200) -> HTTPResponse {

  HTTPResponse(statusCode: status, body: Data(text.utf8))

}

/// What a Hub Pro with a lamp dimmer answers, with invented addresses.
enum Unit {

  static let host = "192.0.2.10"

  static let list = #"[{"location":"","name":"(PLM)","device":"AA.BB.CC","deviceType":"Hub Pro"},{"location":"","name":"Lamp Dimmer","device":"11.22.33","deviceType":"Lamp Dimmer"}]"#

  static let status = #"[{"OnLevel":0,"device":"11.22.33"}]"#

  static let describe = #"{"commands":[{"name":"Beep"},{"name":"On","parameters":["OnLevel"]},{"name":"Off"},{"name":"StatusRequest"},{"name":"WriteLink"},{"name":"ClearLink"}],"devCat":1,"device":"11.22.33","deviceType":"Lamp Dimmer","firmwareVersion":59,"links":{"delta":0,"pending":false,"records":[]},"location":"","name":"Lamp Dimmer","properties":{"LinkMemoryBaseAddress":4095,"LinkMemorySize":417},"removing":false,"sku":"2457D2","subCat":14}"#

  static let statusRequest = #"{"LinkDelta":5,"OnLevel":0,"command":"StatusRequest","device":"11.22.33","result":"successful"}"#

  static let succeeded = #"{"command":"On","device":"11.22.33","result":"successful"}"#

  static let unknownDevice = #"{"command":"insteon/command","device":"00.00.00","error":"Key '00.00.00' not found.","key":"k"}"#

  static let unsupportedKey = #"{"command":"insteon/command","device":"11.22.33","error":"Device 11.22.33 does not support command 'k'.","key":"k"}"#

  static let missingParameters = #"{"command":"insteon/command","error":"The following required parameters were not specified: 'device, key'"}"#

}
