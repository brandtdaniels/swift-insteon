import HTTPTypes

/// One route the server answers. This list is the single description of the HTTP surface: the router
/// registers its routes from it, and `/api/v1/openapi.json` is generated from it, so a route can't
/// exist without being described or be described without existing.
enum APIOperation: String, CaseIterable, Sendable {
  case listDevices, health, executeCommand, streamEvents, openAPI
  case listClients, createClient, revokeClient, createPairing
  case listNotificationRules, putNotificationRule, deleteNotificationRule
  case listRoutes, putRoute, deleteRoute
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
    case .listDevices, .health, .executeCommand, .streamEvents, .openAPI, .listClients, .createClient, .revokeClient, .createPairing, .listNotificationRules, .putNotificationRule, .deleteNotificationRule, .listRoutes, .putRoute, .deleteRoute: true
    case .browserIndex, .browserControls, .browserCard, .browserCommand: false
    }
  }

  var method: HTTPRequest.Method {
    switch self {
    case .executeCommand, .browserCommand, .createClient, .createPairing: .post
    case .revokeClient, .deleteNotificationRule, .deleteRoute: .delete
    case .putNotificationRule, .putRoute: .put
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
    case .listClients, .createClient: "/api/v1/clients"
    case .revokeClient: "/api/v1/clients/{id}"
    case .createPairing: "/api/v1/clients/{id}/pairing"
    case .listNotificationRules: "/api/v1/notification-rules"
    case .putNotificationRule, .deleteNotificationRule: "/api/v1/notification-rules/{id}"
    case .listRoutes: "/api/v1/routes"
    case .putRoute, .deleteRoute: "/api/v1/routes/{kind}"
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
    case .listClients: "List the clients"
    case .createClient: "Create a client and its pairing document"
    case .revokeClient: "Revoke a client"
    case .createPairing: "Replace a client's credential and return its pairing document"
    case .listNotificationRules: "List the notification rules"
    case .putNotificationRule: "Store a notification rule"
    case .deleteNotificationRule: "Remove a notification rule"
    case .listRoutes: "List the routes transports registered"
    case .putRoute: "Register a transport's route"
    case .deleteRoute: "Remove a transport's route"
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
    case .listClients: "The clients without their tokens. Needs the `admin` scope."
    case .createClient: "Creates a client with a name and a scope, and returns the `PairingDocument` that carries its token. The token is shown only here: the service keeps a salted hash. Needs the `admin` scope."
    case .revokeClient: "Removes the client. Its token stops working at once and its open event streams end. Needs the `admin` scope."
    case .createPairing: "Gives the client a new credential and returns it in a `PairingDocument`. The client's previous token stops working and its open event streams end. Needs the `admin` scope."
    case .listNotificationRules: "The rules the service evaluates against what devices report, in the order they were added. Needs the `read` scope."
    case .putNotificationRule: "Adds the rule, or replaces the rule with that identifier. A replacement with the same trigger keeps the rule's cooldown running. The change applies to the next device report. A rule that fires publishes a `notification` event on `/api/v1/events`, which carries the rule, the device and the time, and names the event only when `includeDetail` is true. Needs the `admin` scope."
    case .deleteNotificationRule: "Removes the rule, which stops firing at once. Needs the `admin` scope."
    case .listRoutes: "The routes that separate transport processes registered, in the order they were registered. A pairing document lists them after the `lan` route. A ticket is a locator that only its transport reads, never a secret. Needs the `read` scope."
    case .putRoute: "Registers the route, or replaces the ticket of the route with that kind, which keeps its place. Every pairing document issued afterward lists it; a document issued earlier is unchanged and keeps working, because routes are only hints. Needs the `admin` scope."
    case .deleteRoute: "Removes the route from the pairing documents issued afterward. Needs the `admin` scope."
    case .browserIndex, .browserControls, .browserCard, .browserCommand: "Part of the browser page, not of the versioned API contract."
    }
  }

  private static let addressParameter = Parameter(name: "address", location: "path", required: true, schema: Schema.string(description: "A device address such as 1A.2B.3C."), description: "The device's Insteon address.")

  private static let clientParameter = Parameter(name: "id", location: "path", required: true, schema: Schema.string(description: "A client's identifier."), description: "The client's identifier, from the list or the creation response.")
  private static let ruleParameter = Parameter(name: "id", location: "path", required: true, schema: Schema.string(description: "A rule's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters."), description: "The rule's identifier. A client chooses it.")
  private static let routeParameter = Parameter(name: "kind", location: "path", required: true, schema: Schema.string(pattern: "^[a-z][a-z0-9-]{0,31}$", description: "A transport's identifier: 1 through 32 lowercase letters, digits and `-`, starting with a letter. `lan` is reserved."), description: "The transport's kind. The transport chooses it.")
  private static let markerParameter = Parameter(name: "X-Insteon-Request", location: "header", required: true, schema: Schema.constant("1"), description: "Marks an explicit API request, so a browser page can't change clients by accident.")

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
    case .createClient: [Self.markerParameter]
    case .revokeClient, .createPairing: [Self.clientParameter, Self.markerParameter]
    case .putNotificationRule, .deleteNotificationRule: [Self.ruleParameter, Self.markerParameter]
    case .putRoute, .deleteRoute: [Self.routeParameter, Self.markerParameter]
    case .browserCard, .browserCommand:
      [Self.addressParameter]
    default:
      []
    }
  }

  var requestBody: Body? {
    switch self {
    case .executeCommand: Body(contentType: "application/json", schema: Schema.ref("Command"), description: "The command. Unknown fields are refused. The body is at most 8 KiB.")
    case .createClient: Body(contentType: "application/json", schema: Schema.ref("ClientRequest"), description: "The client's name and scope. Unknown fields are refused.")
    case .putNotificationRule: Body(contentType: "application/json", schema: Schema.ref("NotificationRuleRequest"), description: "The rule without its identifier, which the path gives. Unknown fields are refused. The body is at most 8 KiB.")
    case .putRoute: Body(contentType: "application/json", schema: Schema.ref("RouteRequest"), description: "The route's ticket. Unknown fields are refused. The body is at most 8 KiB.")
    case .browserCommand: Body(contentType: "application/x-www-form-urlencoded", schema: Schema.string(), description: "The page's form: `action`, optional `levelPercent`, and the page's `formKey`.")
    default: nil
    }
  }

  /// The weakest scope a credential needs for the operation. The gateway password is `admin`, and a
  /// browser route takes only the password.
  var requiredScope: ClientScope {
    switch self {
    case .listDevices, .health, .streamEvents, .openAPI, .listNotificationRules, .listRoutes: .read
    case .executeCommand: .control
    case .listClients, .createClient, .revokeClient, .createPairing, .putNotificationRule, .deleteNotificationRule, .putRoute, .deleteRoute: .admin
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
    case .listClients: codes += [.clientsNotSaved]
    case .createClient: codes += [.invalidClient, .clientLimitReached, .clientsNotSaved, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected]
    case .revokeClient, .createPairing: codes += [.unknownClient, .clientsNotSaved, .apiMarkerMissing]
    case .listNotificationRules: codes += [.notificationRulesNotSaved]
    case .putNotificationRule: codes += [.invalidNotificationRule, .unknownDevice, .notificationRuleLimitReached, .notificationRulesNotSaved, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected]
    case .deleteNotificationRule: codes += [.unknownNotificationRule, .notificationRulesNotSaved, .apiMarkerMissing]
    case .listRoutes: codes += [.routeRegistrationsNotSaved]
    case .putRoute: codes += [.invalidRouteRegistration, .routeRegistrationLimitReached, .routeRegistrationsNotSaved, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected]
    case .deleteRoute: codes += [.unknownRouteRegistration, .routeRegistrationsNotSaved, .apiMarkerMissing]
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
    case .listClients: [Reply(status: 200, description: "The clients.", contentType: "application/json", schema: Schema.ref("ClientList"), headers: [:])]
    case .createClient: [Reply(status: 201, description: "The client, and the pairing document that carries its token.", contentType: "application/json", schema: Schema.ref("ClientCreated"), headers: [:])]
    case .revokeClient: [Reply(status: 204, description: "The client is revoked.", contentType: nil, schema: nil, headers: [:])]
    case .createPairing: [Reply(status: 200, description: "The pairing document, with the new credential.", contentType: "application/json", schema: Schema.ref("PairingDocument"), headers: [:])]
    case .listNotificationRules: [Reply(status: 200, description: "The rules.", contentType: "application/json", schema: Schema.ref("NotificationRuleList"), headers: [:])]
    case .putNotificationRule: [Reply(status: 200, description: "The stored rule.", contentType: "application/json", schema: Schema.ref("NotificationRuleStored"), headers: [:])]
    case .listRoutes: [Reply(status: 200, description: "The routes.", contentType: "application/json", schema: Schema.ref("RouteList"), headers: [:])]
    case .putRoute: [Reply(status: 200, description: "The stored route.", contentType: "application/json", schema: Schema.ref("RouteStored"), headers: [:])]
    case .deleteRoute: [Reply(status: 204, description: "The route is removed.", contentType: nil, schema: nil, headers: [:])]
    case .deleteNotificationRule: [Reply(status: 204, description: "The rule is removed.", contentType: nil, schema: nil, headers: [:])]
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
