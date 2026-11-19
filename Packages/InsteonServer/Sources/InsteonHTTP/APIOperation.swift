import HTTPTypes

/// One route the server answers. This list is the single description of the HTTP surface: the router
/// registers its routes from it, and `/api/v1/openapi.json` is generated from it, so a route can't
/// exist without being described or be described without existing.
enum APIOperation: String, CaseIterable, Sendable {
  case listDevices, health, executeCommand, streamEvents, openAPI
  case browserIndex, browserControls, browserCard, browserCommand

  struct Parameter: Sendable {
    let name: String
    let location: String
    let required: Bool
    let schema: JSONValue
    let description: String
  }

  struct Body: Sendable {
    let contentType: String
    let schema: JSONValue
    let description: String
  }

  struct Reply: Sendable {
    let status: Int
    let description: String
    let contentType: String?
    let schema: JSONValue?
    let headers: [String: JSONValue]
  }

  /// The operation a request matched: its method and the route template Hummingbird matched it to.
  init?(method: HTTPRequest.Method, template: String?) {
    guard let template, let match = Self.allCases.first(where: { $0.path == template && $0.method == method }) else { return nil }
    self = match
  }

  /// A browser route answers HTML and plain text for a person; the rest answer machines.
  var isAPI: Bool {
    switch self {
    case .listDevices, .health, .executeCommand, .streamEvents, .openAPI: true
    case .browserIndex, .browserControls, .browserCard, .browserCommand: false
    }
  }

  var method: HTTPRequest.Method {
    switch self {
    case .executeCommand, .browserCommand: .post
    default: .get
    }
  }

  /// The path with `{name}` for each path parameter, as the router and the description both use it.
  var path: String {
    switch self {
    case .listDevices: "/api/v1/devices"
    case .health: "/api/v1/health"
    case .executeCommand: "/api/v1/devices/{address}/commands"
    case .streamEvents: "/api/v1/events"
    case .openAPI: "/api/v1/openapi.json"
    case .browserIndex: "/"
    case .browserControls: "/controls.js"
    case .browserCard, .browserCommand: "/devices/{address}"
    }
  }

  var summary: String {
    switch self {
    case .listDevices: "List the cached devices"
    case .health: "Read readiness and the age of the last hardware exchange"
    case .executeCommand: "Identify, read status, turn on or turn off a device's main group"
    case .streamEvents: "Follow events as server-sent events, resuming from the last id"
    case .openAPI: "Describe this API"
    case .browserIndex: "The browser page"
    case .browserControls: "The browser page's script"
    case .browserCard: "One device's card, from cached state"
    case .browserCommand: "Send a command from a browser form"
    }
  }

  var details: String {
    switch self {
    case .listDevices: "Answers from the cache and sends nothing to hardware. `stale` is true, with the `cause`, while the Hub or modem is away."
    case .health: "Sends nothing to hardware and answers 200 whatever the status."
    case .executeCommand: "A command is sent at most once. With an `Idempotency-Key`, a repeat of the same command returns the recorded answer with `Idempotent-Replay: true` and sends nothing. `sent` in an error says whether a command that changes a device may have reached it."
    case .streamEvents: "Each frame has an SSE `id` of `<runId>-<sequence>` and a JSON `data` line. A client resumes with `Last-Event-ID` (or `lastEventId`) and receives what it missed, or a `gap` frame telling it to refresh everything."
    case .openAPI: "This document. It is generated from the server's route table."
    case .browserIndex, .browserControls, .browserCard, .browserCommand: "Part of the browser page, not of the versioned API contract."
    }
  }

  private static let addressParameter = Parameter(name: "address", location: "path", required: true, schema: Schema.string(description: "A device address such as 1A.2B.3C."), description: "The device's Insteon address.")

  var parameters: [Parameter] {
    switch self {
    case .executeCommand:
      [
        Self.addressParameter,
        Parameter(name: "X-Insteon-Request", location: "header", required: true, schema: Schema.constant("1"), description: "Marks an explicit API request, so a browser page can't send a command by accident."),
        Parameter(name: "Idempotency-Key", location: "header", required: false, schema: Schema.string(pattern: IdempotencyKey.pattern), description: "A token the client picks, 1 through 128 characters. A repeat with the same key and command returns the recorded answer.")
      ]
    case .streamEvents:
      [
        Parameter(name: "Last-Event-ID", location: "header", required: false, schema: Schema.string(), description: "The id of the last frame the client saw. A browser's EventSource sends it by itself."),
        Parameter(name: "lastEventId", location: "query", required: false, schema: Schema.string(), description: "The same, for a client that can't set headers. The header wins.")
      ]
    case .browserCard, .browserCommand:
      [Self.addressParameter]
    default:
      []
    }
  }

  var requestBody: Body? {
    switch self {
    case .executeCommand: Body(contentType: "application/json", schema: Schema.ref("Command"), description: "The command. Unknown fields are refused. The body is at most 8 KiB.")
    case .browserCommand: Body(contentType: "application/x-www-form-urlencoded", schema: Schema.string(), description: "The page's form: `action`, optional `levelPercent`, and the page's `formKey`.")
    default: nil
    }
  }

  /// The weakest scope a credential needs for the operation. The gateway password is `admin`, and a
  /// browser route takes only the password.
  var requiredScope: ClientScope {
    switch self {
    case .listDevices, .health, .streamEvents, .openAPI: .read
    case .executeCommand: .control
    case .browserIndex, .browserControls, .browserCard, .browserCommand: .admin
    }
  }

  /// Whether a client token authenticates the operation. A browser route takes the gateway password only.
  var acceptsClientTokens: Bool { isAPI }

  /// The failures the operation can answer with, besides the ones every authenticated route has.
  var errorCodes: [APIErrorCode] {
    var codes: [APIErrorCode] = [.authenticationRequired, .authenticationFailed]
    if isAPI, requiredScope > .read { codes.append(.forbidden) }
    switch self {
    case .executeCommand:
      codes += [.invalidAddress, .invalidCommand, .invalidLevel, .invalidIdempotencyKey, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected, .unknownDevice, .idempotencyKeyReused, .busy, .notIdentified, .notLinked, .unsupportedControl, .deviceRejected, .modemRejected, .modemUnavailable, .canceled, .deviceNotAnswering, .outcomeUnknown]
    case .browserCard:
      codes += [.invalidAddress, .unknownDevice, .busy]
    case .browserCommand:
      codes += [.invalidAddress, .invalidCommand, .invalidLevel, .formKeyInvalid, .unsupportedMediaType, .bodyTooLarge, .unknownDevice, .busy, .notIdentified, .notLinked, .unsupportedControl, .deviceRejected, .modemRejected, .modemUnavailable, .deviceNotAnswering, .outcomeUnknown]
    default:
      break
    }
    return codes
  }

  private var successes: [Reply] {
    switch self {
    case .listDevices: [Reply(status: 200, description: "The cached devices.", contentType: "application/json", schema: Schema.ref("DeviceList"), headers: [:])]
    case .health: [Reply(status: 200, description: "The service's readiness.", contentType: "application/json", schema: Schema.ref("Health"), headers: [:])]
    case .executeCommand: [Reply(status: 200, description: "The command's receipt.", contentType: "application/json", schema: Schema.ref("Receipt"), headers: ["Idempotent-Replay": ["$ref": "#/components/headers/IdempotentReplay"]])]
    case .streamEvents: [Reply(status: 200, description: "A stream of frames. It ends cleanly after 10 minutes, and the client reconnects with its last id.", contentType: "text/event-stream", schema: Schema.ref("StreamFrame"), headers: [:])]
    case .openAPI: [Reply(status: 200, description: "The OpenAPI 3.1 description.", contentType: "application/json", schema: Schema.ref("OpenAPIDocument"), headers: [:])]
    case .browserIndex: [Reply(status: 200, description: "The page.", contentType: "text/html", schema: nil, headers: [:])]
    case .browserControls: [Reply(status: 200, description: "The script.", contentType: "text/javascript", schema: nil, headers: [:])]
    case .browserCard: [Reply(status: 200, description: "The device's card.", contentType: "text/html", schema: nil, headers: [:])]
    case .browserCommand: [
      Reply(status: 200, description: "With `X-Insteon-Fragment: device`, the device's card, with the failure on it when the command failed.", contentType: "text/html", schema: nil, headers: [:]),
      Reply(status: 303, description: "Without it, a redirect to the page, with the failure in the query when the command failed.", contentType: nil, schema: nil, headers: ["Location": ["description": "The page.", "schema": ["type": "string"]]])
    ]
    }
  }

  /// The success replies, then one reply per status the operation's failures use.
  var replies: [Reply] {
    var replies = successes
    var byStatus: [Int: [APIErrorCode]] = [:]
    for code in errorCodes { byStatus[Int(code.status.code), default: []].append(code) }
    for status in byStatus.keys.sorted() where !replies.contains(where: { $0.status == status }) {
      let codes = byStatus[status] ?? []
      var headers: [String: JSONValue] = [:]
      if status == 401 { headers["WWW-Authenticate"] = ["description": "The Basic challenge.", "schema": ["type": "string"]] }
      if self == .executeCommand { headers["Idempotent-Replay"] = ["$ref": "#/components/headers/IdempotentReplay"] }
      replies.append(Reply(
        status: status,
        description: "Failure: " + codes.map(\.rawValue).joined(separator: ", ") + ".",
        contentType: isAPI ? "application/json" : "text/plain",
        schema: isAPI ? Schema.ref("Error") : nil,
        headers: headers
      ))
    }
    return replies
  }
}
