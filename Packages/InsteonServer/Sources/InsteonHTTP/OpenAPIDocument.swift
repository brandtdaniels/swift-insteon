import Foundation
import InsteonService

/// The OpenAPI 3.1 description of the server, built from ``APIOperation``, ``APIErrorCode`` and the
/// wire vocabulary. Nothing in it is typed twice: routes, error codes and enumerations come from the
/// Swift types that implement them, and the tests encode the real response types and check that they
/// satisfy the schemas written here.
enum OpenAPIDocument {
  /// The document, encoded with sorted keys, so every request returns the same bytes.
  static let bytes: Data = (try? document.encoded()) ?? Data()

  static var document: JSONValue {
    [
      "openapi": "3.1.0",
      "info": [
        "title": "Insteon gateway API",
        "version": "1",
        "summary": "Control and monitor an Insteon network through a Hub or a serial modem.",
        "description": "Version 1 of the gateway's JSON API. Additions inside /api/v1 are compatible: new optional fields, new error codes and new event kinds. Removing or retyping a field, changing an error's status classification or the event id format needs /api/v2. Clients ignore fields and event kinds they don't know. A path the server doesn't serve answers 404 `routeNotFound`. Send the gateway password as Basic authentication or a client token as `Authorization: Bearer`; each operation lists the least scope it needs."
      ],
      "servers": [["url": "/"]],
      "security": [["bearerAuth": []], ["basicAuth": []]],
      "paths": .object(paths),
      "components": [
        "securitySchemes": [
          "basicAuth": ["type": "http", "scheme": "basic", "description": "The gateway password, with any user name. It has the `admin` scope."],
          "bearerAuth": ["type": "http", "scheme": "bearer", "description": "A client token. The scopes listed in an operation's security requirement are the least one the client needs: `read` reads and follows events, `control` also sends commands, `admin` also manages clients."]
        ],
        "headers": ["IdempotentReplay": [
          "description": "`true` when the response repeats an earlier answer to the same Idempotency-Key and the command wasn't sent again.",
          "schema": Schema.constant("true")
        ]],
        "schemas": .object(schemas)
      ]
    ]
  }

  // MARK: Paths

  private static var paths: [String: JSONValue] {
    var paths: [String: JSONValue] = [:]
    for operation in APIOperation.allCases {
      var item = paths[operation.path]?.members ?? [:]
      item[operation.method.rawValue.lowercased()] = describe(operation)
      paths[operation.path] = .object(item)
    }
    return paths
  }

  private static func describe(_ operation: APIOperation) -> JSONValue {
    var members: [String: JSONValue] = [
      "operationId": .string(operation.rawValue),
      "summary": .string(operation.summary),
      "description": .string(operation.details),
      "tags": [operation.isAPI ? "api" : "browser"],
      "x-required-scope": .string(operation.requiredScope.rawValue),
      "security": operation.acceptsClientTokens ? [["bearerAuth": [.string(operation.requiredScope.rawValue)]], ["basicAuth": []]] : [["basicAuth": []]],
      "responses": .object(Dictionary(uniqueKeysWithValues: operation.replies.map { (String($0.status), describe($0)) }))
    ]
    if !operation.parameters.isEmpty {
      members["parameters"] = .array(operation.parameters.map { parameter in
        ["name": .string(parameter.name), "in": .string(parameter.location), "required": .bool(parameter.required), "description": .string(parameter.description), "schema": parameter.schema]
      })
    }
    if let body = operation.requestBody {
      members["requestBody"] = ["required": true, "description": .string(body.description), "content": .object([body.contentType: ["schema": body.schema]])]
    }
    return .object(members)
  }

  private static func describe(_ reply: APIOperation.Reply) -> JSONValue {
    var members: [String: JSONValue] = ["description": .string(reply.description)]
    if let contentType = reply.contentType {
      members["content"] = .object([contentType: reply.schema.map { ["schema": $0] } ?? [:]])
    }
    if !reply.headers.isEmpty { members["headers"] = .object(reply.headers) }
    return .object(members)
  }

  // MARK: Schemas

  private static let address = Schema.string(description: "An Insteon address such as 1A.2B.3C.")
  private static let version = JSONValue.object(["type": "integer", "const": 1, "description": "The wire format's version."])

  private static var schemas: [String: JSONValue] {
    let causes = ModemUnavailability.allWireNames
    return [
      "ErrorCode": [
        "type": "string",
        "enum": .array(APIErrorCode.allCases.map { .string($0.rawValue) }),
        "description": "A stable code to branch on. A new code is an additive change.",
        "x-codes": .array(APIErrorCode.allCases.map { code in
          ["code": .string(code.rawValue), "status": .integer(Int(code.status.code)), "sent": .bool(code.sent), "message": .string(code.message)]
        })
      ],
      "ModemCause": Schema.string(enum: causes, description: "Why the Hub or modem is away."),
      "Error": Schema.object([
        "version": version,
        "code": Schema.ref("ErrorCode"),
        "message": Schema.string(description: "For a person. The wording can change."),
        "sent": ["type": "boolean", "description": "True only when a command that changes a device may have reached it, so repeating the command could repeat the change."],
        "requestId": Schema.string(description: "The request_id of the log record for this request."),
        "cause": Schema.ref("ModemCause")
      ], required: ["version", "code", "message", "sent", "requestId"], description: "Every non-2xx response of an API route."),
      "Command": Schema.object([
        "action": Schema.string(enum: HTTPCommand.Action.allCases.map(\.rawValue)),
        "levelPercent": Schema.integer(minimum: 0, maximum: 100, description: "Only for `on`, and only for a device that dims.")
      ], required: ["action"]),
      "Status": Schema.object([
        "group": Schema.nullable(Schema.integer()),
        "kind": Schema.string(enum: ReadingKind.allCases.map(\.rawValue)),
        "value": Schema.integer(minimum: 0, maximum: 255),
        "isOn": Schema.boolean,
        "percent": Schema.nullable(Schema.integer(minimum: 0, maximum: 100)),
        "label": Schema.nullable(Schema.string())
      ], required: ["kind", "value", "isOn"]),
      "Receipt": Schema.object([
        "version": version,
        "address": address,
        "outcome": Schema.string(enum: ReceiptOutcome.allCases.map(\.rawValue)),
        "status": Schema.ref("Status"),
        "persistence": Schema.ref("Persistence")
      ], required: ["version", "address", "outcome", "persistence"], description: "An acknowledged control is not a status reading."),
      "Persistence": Schema.string(enum: PersistenceName.allCases.map(\.rawValue), description: "Whether the snapshot was saved, independent of the device result."),
      "Device": Schema.object([
        "address": address,
        "productName": Schema.nullable(Schema.string()),
        "canTurnOnAndOff": Schema.boolean,
        "canDim": Schema.boolean,
        "value": Schema.nullable(Schema.integer(minimum: 0, maximum: 255)),
        "lastAnsweredAt": Schema.nullable(["type": "string", "format": "date-time"])
      ], required: ["address", "canTurnOnAndOff", "canDim"]),
      "DeviceList": Schema.object([
        "version": version,
        "devices": Schema.array(of: Schema.ref("Device")),
        "stale": Schema.boolean,
        "cause": Schema.nullable(Schema.ref("ModemCause"))
      ], required: ["version", "devices", "stale", "cause"]),
      "Health": Schema.object([
        "version": version,
        "status": Schema.string(enum: HealthStatusName.allCases.map(\.rawValue)),
        "modem": Schema.object(["connected": Schema.boolean, "cause": Schema.nullable(Schema.ref("ModemCause"))], required: ["connected", "cause"]),
        "lastExchangeAgeSeconds": Schema.nullable(Schema.integer(minimum: 0)),
        "lastPollAgeSeconds": Schema.nullable(Schema.integer(minimum: 0)),
        "snapshotAgeSeconds": Schema.nullable(Schema.integer(minimum: 0)),
        "persistence": Schema.ref("Persistence")
      ], required: ["version", "status", "modem", "lastExchangeAgeSeconds", "lastPollAgeSeconds", "snapshotAgeSeconds", "persistence"]),
      "CommandCompletion": Schema.object([
        "action": Schema.string(enum: HTTPCommand.Action.allCases.map(\.rawValue)),
        "levelPercent": Schema.nullable(Schema.integer(minimum: 0, maximum: 100)),
        "result": Schema.ref("Receipt")
      ], required: ["action", "levelPercent", "result"]),
      "Event": Schema.object([
        "version": version,
        "runId": Schema.string(description: "Names the service run. Different at every start."),
        "sequence": Schema.integer(minimum: 0, description: "The event's number in the run: 1, 2, 3. Shared by every client."),
        "kind": Schema.string(enum: EventKind.allCases.filter { $0 != .gap }.map(\.rawValue)),
        "address": Schema.nullable(address),
        "group": Schema.nullable(Schema.integer()),
        "name": Schema.nullable(Schema.string()),
        "productName": Schema.nullable(Schema.string()),
        "completion": Schema.nullable(Schema.ref("CommandCompletion")),
        "cause": Schema.nullable(Schema.ref("ModemCause")),
        "message": Schema.nullable(Schema.string()),
        "ruleId": Schema.string(description: "On `notification`: the rule's identifier."),
        "ruleName": Schema.string(description: "On `notification`: the rule's name."),
        "firedAt": ["type": "string", "format": "date-time", "description": "On `notification`: when the rule fired."]
      ], required: ["version", "runId", "sequence", "kind"], description: "The `data` of one frame. `commandCompleted` carries `completion`; `modemUnavailable` carries `cause` and `message`; `reconnected` says the modem is back and a client refreshes what it shows. `notification` carries `ruleId`, `ruleName`, the device as `address` and `firedAt`, and `name` only when the rule includes detail."),
      "Gap": Schema.object([
        "version": version,
        "kind": Schema.constant(EventKind.gap.rawValue),
        "reason": Schema.string(enum: EventGapReason.allCases.map(\.rawValue), description: "`otherRun`: the service restarted or the id isn't one it made. `tooOld`: the events after the id were dropped (the newest 256 are kept). `ahead`: the id is past the run's newest event."),
        "runId": Schema.string(),
        "sequence": Schema.integer(minimum: 0)
      ], required: ["version", "kind", "reason", "runId", "sequence"], description: "The client missed events the server can't replay. It refreshes everything it shows, then continues with the frames that follow."),
      "StreamFrame": [
        "oneOf": [Schema.ref("Event"), Schema.ref("Gap")],
        "description": "The JSON of one `data` line. The frame's SSE `id` is `<runId>-<sequence>`; send it back as `Last-Event-ID`. Lines that start with a colon are keepalives, and a frame with an `id` and no data sets the client's place."
      ],
      "NotificationTrigger": [
        "oneOf": [
          Schema.object(["kind": Schema.constant(NotificationTriggerKind.event.rawValue), "event": Schema.string(description: "An event the device's product reports, in lower camel case, such as `wet`."), "device": address], required: ["kind", "event", "device"]),
          Schema.object(["kind": Schema.constant(NotificationTriggerKind.groupCommand.rawValue), "command1": Schema.integer(minimum: 0, maximum: 255), "group": Schema.integer(minimum: 1, maximum: 255), "device": address], required: ["kind", "command1", "group", "device"])
        ],
        "description": "What makes a rule fire: a device reports an event its product's profile names, or sends a command to one of its groups. A heartbeat is not a group command here."
      ],
      "NotificationRule": Schema.object([
        "id": Schema.string(description: "The rule's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters."),
        "name": Schema.string(description: "1 through 64 characters, without control characters."),
        "trigger": Schema.ref("NotificationTrigger"),
        "cooldownSeconds": Schema.integer(minimum: 0, maximum: ServiceNotificationRule.longestCooldownSeconds, description: "Seconds the rule stays quiet after it fires."),
        "enabled": Schema.boolean,
        "includeDetail": ["type": "boolean", "description": "Whether a notification names the event. Off, a notification carries only the rule, the device and the time."]
      ], required: ["id", "name", "trigger", "cooldownSeconds", "enabled", "includeDetail"]),
      "NotificationRuleList": Schema.object(["version": version, "rules": Schema.array(of: Schema.ref("NotificationRule"))], required: ["version", "rules"]),
      "NotificationRuleStored": Schema.object(["version": version, "rule": Schema.ref("NotificationRule")], required: ["version", "rule"]),
      "NotificationRuleRequest": Schema.object([
        "name": Schema.string(description: "1 through 64 characters, without control characters."),
        "trigger": Schema.ref("NotificationTrigger"),
        "cooldownSeconds": Schema.integer(minimum: 0, maximum: ServiceNotificationRule.longestCooldownSeconds, description: "Defaults to 0."),
        "enabled": Schema.boolean,
        "includeDetail": Schema.boolean
      ], required: ["name", "trigger"], description: "A rule without its identifier. Defaults: `cooldownSeconds` 0, `enabled` true, `includeDetail` false."),
      "ClientScope": Schema.string(enum: ClientScope.allCases.map(\.rawValue), description: "What a credential may do. `read` reads devices and health and follows events. `control` also sends commands. `admin` also manages clients. The gateway password is `admin`."),
      "Client": Schema.object([
        "id": Schema.string(description: "The identifier in the client's token and in `/api/v1/clients/{id}`."),
        "name": Schema.string(description: "A name a person chose."),
        "scope": Schema.ref("ClientScope"),
        "createdAt": ["type": "string", "format": "date-time"]
      ], required: ["id", "name", "scope", "createdAt"], description: "A client of the service. Its token is never part of it."),
      "ClientList": Schema.object(["version": version, "clients": Schema.array(of: Schema.ref("Client"))], required: ["version", "clients"]),
      "ClientRequest": Schema.object([
        "name": Schema.string(description: "1 through 64 characters, without control characters."),
        "scope": Schema.ref("ClientScope")
      ], required: ["name", "scope"]),
      "ClientCreated": Schema.object(["version": version, "client": Schema.ref("Client"), "pairing": Schema.ref("PairingDocument")], required: ["version", "client", "pairing"]),
      "PairingRoute": [
        "type": "object",
        "required": ["kind"],
        "properties": [
          "kind": Schema.string(description: "`lan` for a direct address, or the identifier of a transport. A client skips a kind it doesn't know."),
          "url": Schema.string(description: "Where a `lan` route is reached."),
          "ticket": Schema.string(description: "What a transport needs to reach the service. Only that transport reads it.")
        ],
        "description": "One way to reach the service. A client tries a document's routes in order and uses the first that answers `GET /api/v1/health`."
      ],
      "PairingDocument": [
        "type": "object",
        "required": ["version", "serviceId", "name", "credential", "scope", "api", "routes"],
        "properties": [
          "version": version,
          "serviceId": Schema.string(description: "Names the service, the same for every client that pairs with it."),
          "name": Schema.string(description: "The home's name, for a client to show."),
          "credential": Schema.string(description: "The client's token. Send it as `Authorization: Bearer <credential>`. It is shown once."),
          "scope": Schema.ref("ClientScope"),
          "api": Schema.string(description: "The path every API route sits under."),
          "routes": Schema.array(of: Schema.ref("PairingRoute"))
        ],
        "description": "What a client needs to pair with the service. A reader ignores fields it doesn't know."
      ],
      "OpenAPIDocument": [
        "type": "object",
        "required": ["openapi", "info", "paths"],
        "description": "An OpenAPI 3.1 document."
      ]
    ]
  }
}

extension JSONValue {
  fileprivate var members: [String: JSONValue]? {
    if case let .object(members) = self { members } else { nil }
  }
}
