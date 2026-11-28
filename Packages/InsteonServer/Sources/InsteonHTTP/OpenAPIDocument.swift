import Foundation
import InsteonCore
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
      "SceneCommand": Schema.object([
        "action": Schema.string(enum: HTTPSceneAction.allCases.map(\.rawValue))
      ], required: ["action"]),
      "SceneMembershipRequest": Schema.object([
        "add": Schema.array(of: Schema.object([
          "device": address,
          "onLevel": Schema.integer(minimum: 0, maximum: 255, description: "What the member's record holds for the on-level. Left out, the record holds full on (255). A device whose record has no on-level byte refuses it."),
          "rampRate": Schema.integer(minimum: 0, maximum: 255, description: "What the member's record holds for the ramp rate. Left out, the record holds 0.5 s (28). A device whose record has no ramp rate byte refuses it."),
          "group": Schema.integer(minimum: 1, maximum: 255, description: "The device's own group that answers the scene, such as one button of a keypad. Left out, the device's main group. The catalog must give the device the group, or the plan refuses it as `unknownGroup`.")
        ], required: ["device"])),
        "remove": Schema.array(of: [
          "oneOf": [
            address,
            Schema.object([
              "device": address,
              "group": Schema.integer(minimum: 1, maximum: 255, description: "The device's own group to remove, such as one button of a keypad. The modem's record of the device goes when no group of it stays in the scene.")
            ], required: ["device"])
          ],
          "description": "A device's address removes all of its records of the scene, or an object names one group of it."
        ])
      ], required: [], description: "At least one device in all and at most 32 in each list. A device named twice for the same group, or in both lists, is refused in the plan as `duplicateEntry` or `addedAndRemoved`."),
      "SceneMembershipPlan": Schema.object([
        "version": version,
        "scene": Schema.integer(minimum: 1, maximum: 254),
        "planId": Schema.string(pattern: "^sha256:[0-9a-f]{64}$", description: "A hash of the scene, the steps and the records they were made from, the same as the consent's `readFingerprint`. The service keeps a plan it could apply in memory by this id until `expiresAt`."),
        "expiresAt": ["type": "string", "format": "date-time", "description": "Five minutes after the plan was made."],
        "isApplicable": ["type": "boolean", "description": "Whether the plan has steps and no refusal."],
        "isEmpty": ["type": "boolean", "description": "Whether the plan writes nothing."],
        "steps": Schema.array(of: Schema.ref("SceneMembershipStep")),
        "devices": Schema.array(of: Schema.ref("SceneMembershipDevice")),
        "warnings": Schema.array(of: Schema.ref("SceneMembershipFinding")),
        "refusals": Schema.array(of: Schema.ref("SceneMembershipFinding")),
        "consent": Schema.nullable(Schema.ref("SceneMembershipConsent"))
      ], required: ["version", "scene", "planId", "expiresAt", "isApplicable", "isEmpty", "steps", "devices", "warnings", "refusals", "consent"], description: "What adding and removing a scene's members would write, made from the cached databases and the catalog. Nothing was written or sent."),
      "SceneMembershipStep": Schema.object([
        "order": Schema.integer(minimum: 1),
        "kind": Schema.string(enum: SceneMembershipStep.Kind.allCases.map(\.rawValue), description: "What the step writes. A device's record is added to a free slot, or to the end's with the end marked one slot below first; the modem's record is added or deleted; a record in use is changed in place only by `updateDeviceRecord`."),
        "target": Schema.string(description: "`modem`, or the address of the device whose database the step writes."),
        "effect": Schema.string(enum: ["write", "delete"]),
        "record": Schema.ref("SceneMembershipRecord"),
        "updateInPlace": ["type": "boolean", "description": "Whether the step rewrites a record in use. The plan refuses such a step as `notYetSupported`."],
        "risks": Schema.array(of: Schema.string(enum: SceneMembershipStep.Risk.allCases.map(\.rawValue), description: "What can go wrong with the step beyond a write that does not read back."))
      ], required: ["order", "kind", "target", "effect", "record", "updateInPlace", "risks"]),
      "SceneMembershipRecord": Schema.object([
        "role": Schema.string(enum: ["controller", "responder"]),
        "group": Schema.integer(minimum: 0, maximum: 255),
        "address": address,
        "data": Schema.array(of: Schema.integer(minimum: 0, maximum: 255)),
        "memoryAddress": Schema.nullable(Schema.string(pattern: "^0x[0-9A-F]{4}$", description: "Where the record is in a device's database. Null for the modem's."))
      ], required: ["role", "group", "address", "data", "memoryAddress"], description: "The record as the step leaves it: for a responder record of a member, `data` is the on-level, the ramp rate and the member's own group as the catalog gives them. A deleted record is not in use."),
      "SceneMembershipDevice": Schema.object([
        "address": address,
        "product": Schema.nullable(Schema.string()),
        "engine": Schema.nullable(Schema.string(enum: ["i1", "i2", "i2cs"])),
        "acceptsRemoteWrite": ["type": "boolean", "description": "Whether the device's engine takes a remote write of its ALL-Link database, it does not reject the modem, and its cached database was read whole."]
      ], required: ["address", "product", "engine", "acceptsRemoteWrite"]),
      "SceneMembershipFinding": Schema.object([
        "code": Schema.string(enum: SceneMembershipFinding.Code.allCases.map(\.rawValue)),
        "device": Schema.nullable(address),
        "detail": Schema.nullable(Schema.string())
      ], required: ["code", "device", "detail"], description: "A warning, or a reason the plan can't be applied. A null `device` is the modem."),
      "SceneMembershipConsent": Schema.object([
        "writeLinkRecords": ["type": "boolean", "const": true],
        "readFingerprint": Schema.string(pattern: "^sha256:[0-9a-f]{64}$", description: "Names the steps and the records they were made from.")
      ], required: ["writeLinkRecords", "readFingerprint"], description: "What applying the plan will need: the consent that applying a database link plan takes."),
      "SceneMembershipApplyRequest": Schema.object([
        "consent": Schema.object([
          "writeLinkRecords": ["type": "boolean", "const": true, "description": "Agrees that ALL-Link records are written. A missing or false value is `consentRequired`."],
          "readFingerprint": Schema.string(pattern: "^sha256:[0-9a-f]{64}$", description: "The plan's `consent.readFingerprint`, which names the steps and the records they were made from. Another plan's is `consentMismatch`.")
        ], required: ["writeLinkRecords", "readFingerprint"])
      ], required: ["consent"], description: "The consent the plan answered with. There is no `force`: a plan never overwrites a record in use, and any other field is refused. A consent that is missing or does not agree is `consentRequired` (422), whatever the credential's scope."),
      "SceneMembershipApplication": Schema.object([
        "version": version,
        "scene": Schema.integer(minimum: 1, maximum: 254),
        "planId": Schema.string(pattern: "^sha256:[0-9a-f]{64}$"),
        "outcome": Schema.string(enum: ["applied", "appliedUnverified", "incomplete"], description: "`applied` when every step was made and both databases read back as planned. `appliedUnverified` (200) when every step was made and no record was found other than expected, but reading the databases again did not finish, so a client refreshes the scenes and checks. `incomplete` (502) when a step was not made or a record was found other than expected."),
        "isComplete": ["type": "boolean"],
        "written": Schema.integer(minimum: 0, description: "How many steps were made."),
        "notWritten": Schema.integer(minimum: 0, description: "How many steps were not made: failed, or not reached because an earlier one failed."),
        "steps": Schema.array(of: Schema.ref("SceneMembershipAppliedStep")),
        "mismatches": Schema.array(of: Schema.ref("SceneMembershipMismatch")),
        "modemChecked": ["type": "boolean", "description": "Whether the modem's database was read again and compared with what the steps made should have left."],
        "deviceChecks": Schema.array(of: Schema.object([
          "device": address,
          "check": Schema.string(enum: DatabaseLinkResult.DeviceCheck.allCases.map(\.rawValue), description: "`checked` when the device's database was read again and compared, `rejectsModemAfterUnlinking` when an i2CS device rejects the modem once its last record of the modem is gone, `unanswered` when it did not answer.")
        ], required: ["device", "check"])),
        "interruption": Schema.nullable(Schema.string(enum: ["canceled", "failed"], description: "Why the steps stopped for a reason other than a step's own failure.")),
        "interruptionDetail": Schema.nullable(Schema.string(description: "For `failed`: the modem's error without an address or credential.")),
        "cacheReload": Schema.string(enum: ["reloaded", "failed"], description: "`reloaded` when the service read the modem's database and the databases of the devices the steps touched into its cache afterward, so `GET /api/v1/scenes` shows the change. `failed` when it could not read the modem or a device that should be readable, and the listing holds the records as they were until a client refreshes the scenes. A device that rejects the modem once its last record of it is removed is expected unreadable: it is listed in `expectedUnreadable` and does not make this `failed`."),
        "expectedUnreadable": Schema.array(of: address),
        "persistence": Schema.ref("Persistence"),
        "code": Schema.ref("ErrorCode"),
        "message": Schema.string(description: "Present when `appliedUnverified` or `incomplete`. For a person, from the counts of steps made and records found."),
        "sent": ["type": "boolean", "const": true, "description": "Present when `incomplete`: ALL-Link records may have been written."],
        "requestId": Schema.string(description: "Present when `incomplete`: the request_id of the log record for this request.")
      ], required: ["version", "scene", "planId", "outcome", "isComplete", "written", "notWritten", "steps", "mismatches", "modemChecked", "deviceChecks", "interruption", "interruptionDetail", "cacheReload", "expectedUnreadable", "persistence"], description: "What applying a plan did. An `incomplete` answer is also an error body (`code` `outcomeUnknown`, `sent` true): the steps before the first failure are written, the failed one may be, and the rest were not made. The service never rolls back, so a client plans again from a fresh read."),
      "SceneMembershipAppliedStep": Schema.object([
        "order": Schema.integer(minimum: 1),
        "kind": Schema.string(enum: SceneMembershipStep.Kind.allCases.map(\.rawValue)),
        "target": Schema.string(description: "`modem`, or the address of the device whose database the step writes."),
        "effect": Schema.string(enum: ["write", "delete"]),
        "record": Schema.ref("SceneMembershipRecord"),
        "outcome": Schema.string(enum: DatabaseLinkStepOutcome.allCases.map(\.rawValue), description: "`written` and `writtenOnRetry` read back as written; `unverifiable` removed an i2CS device's last record of the modem, which then rejects the modem; `notWritten` read back differently twice; `rejected` was rejected each time; `unanswered` got no answer, so whether it took is not known; `notReached` was not made because an earlier step failed.")
      ], required: ["order", "kind", "target", "effect", "record", "outcome"]),
      "SceneMembershipMismatch": Schema.object([
        "target": Schema.string(description: "`modem`, or the address of the device whose database holds the record."),
        "memoryAddress": Schema.nullable(Schema.string(pattern: "^0x[0-9A-F]{4}$")),
        "expected": Schema.nullable(Schema.ref("SceneMembershipRecord")),
        "found": Schema.nullable(Schema.ref("SceneMembershipRecord"))
      ], required: ["target", "memoryAddress", "expected", "found"], description: "A record that reading the database again did not find as the steps made should have left it."),
      "SceneReceipt": Schema.object([
        "version": version,
        "scene": Schema.integer(minimum: 1, maximum: 254),
        "action": Schema.string(enum: HTTPSceneAction.allCases.map(\.rawValue)),
        "outcome": Schema.string(enum: ReceiptOutcome.allCases.map(\.rawValue)),
        "acknowledged": ["type": "array", "items": address, "description": "The members that acknowledged their ALL-Link cleanup. Empty for a modem that passes no per-member acknowledgment up, which never means that no member acted."],
        "unacknowledged": ["type": "array", "items": address, "description": "The members that did not acknowledge their cleanup and may still have acted."],
        "isComplete": ["type": "boolean", "description": "Whether the modem reports that it sent every member its cleanup."],
        "responderCount": Schema.integer(minimum: 0, description: "How many members the scene had when it ran."),
        "persistence": Schema.ref("Persistence")
      ], required: ["version", "scene", "action", "outcome", "acknowledged", "unacknowledged", "isComplete", "responderCount", "persistence"], description: "How a scene's command went. The service does not read the members afterward."),
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
        "persistence": Schema.ref("Persistence"),
        "notes": Schema.array(of: Schema.ref("HealthNote")),
        "tuning": Schema.array(of: Schema.ref("TuningValue"))
      ], required: ["version", "status", "modem", "lastExchangeAgeSeconds", "lastPollAgeSeconds", "snapshotAgeSeconds", "persistence"]),
      "TuningValue": Schema.object([
        "name": Schema.string(description: "The setting, such as `scenes.echoWaitMs`. A client ignores a name it doesn't know."),
        "value": Schema.integer(minimum: 0, description: "The value in use, in the unit."),
        "unit": Schema.constant("ms"),
        "source": Schema.string(enum: ["default", "flag", "environment"], description: "Where the value came from: the standard value, a command-line option or an environment variable.")
      ], required: ["name", "value", "unit", "source"], description: "A setting that tunes how the service waits, with its effective value. The standard values are unverified."),
      "HealthNote": Schema.object([
        "code": Schema.string(enum: HealthNoteCode.allCases.map(\.rawValue)),
        "message": Schema.string(description: "For a person. The wording can change.")
      ], required: ["code", "message"], description: "Something worth knowing that doesn't change what the service can do, such as a time zone the host doesn't have, or a Hub whose clock differs from the service's. A client ignores a code it doesn't know."),
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
        "firedAt": ["type": "string", "format": "date-time", "description": "On `notification`: when the rule fired. On `schedule`: when the service handled the run."],
        "scheduleId": Schema.string(description: "On `schedule`: the schedule's or timer's identifier."),
        "source": Schema.string(enum: ScheduleSourceName.allCases.map(\.rawValue) + SceneSourceName.allCases.map(\.rawValue), description: "On `schedule`: whether a schedule or a timer ran. On `scene`: `api`, a client's request."),
        "outcome": Schema.string(enum: ScheduleOutcomeName.allCases.map(\.rawValue), description: "On `schedule`: `acknowledged` when the device acknowledged the command; `missed` when the run time passed while the service wasn't running or the clock moved past it, so nothing was sent; `unavailable` when the Hub or modem was away, so nothing was sent (`cause` says why); `refused` when the service refused the command before sending it (`reason` is the error code); `unknown` when the command may have reached the device. A run is never retried."),
        "reason": Schema.string(description: "On `schedule` with outcome `refused`: the error code the same command would answer with."),
        "scene": Schema.integer(minimum: 1, maximum: 254, description: "On `scene`: the scene's group number."),
        "action": Schema.string(enum: HTTPSceneAction.allCases.map(\.rawValue), description: "On `scene`: what the scene was told to do."),
        "acknowledged": ["type": "array", "items": address, "description": "On `scene`: the members that acknowledged their ALL-Link cleanup. Empty for a modem that passes no per-member acknowledgment up, so an empty list never means no member acted."],
        "unacknowledged": ["type": "array", "items": address, "description": "On `scene`: the members that did not acknowledge their cleanup and may still have acted."],
        "isComplete": ["type": "boolean", "description": "On `scene`: for a run, whether the modem sent every member its cleanup. For a membership change, whether every step of the applied plan was made and both databases read back as planned."],
        "change": Schema.string(enum: ["membership"], description: "On `scene`: `membership` when a plan was applied and the scene's members changed or may have, in whole or in part. A client reads the scenes again. Absent for a run, which carries `action`, `acknowledged` and `unacknowledged` instead."),
        "nextRun": Schema.nullable(["type": "string", "format": "date-time", "description": "On `schedule`: when the schedule runs next, in the service's time zone, or null for a timer or a schedule with no run to come."])
      ], required: ["version", "runId", "sequence", "kind"], description: "The `data` of one frame. `commandCompleted` carries `completion`; `modemUnavailable` carries `cause` and `message`; `reconnected` says the modem is back and a client refreshes what it shows. `notification` carries `ruleId`, `ruleName`, the device as `address` and `firedAt`, and `name` only when the rule includes detail. `schedule` carries `scheduleId`, `name`, `source`, the device as `address`, `outcome`, `firedAt` and `nextRun`. `scene` carries `scene`, `name` (null when the scene has no name), `source` (`api`), `action`, `acknowledged`, `unacknowledged`, `isComplete` and `firedAt`. A scene run by a member's button or the command line is not reported, because the modem does not report its own group sends."),
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
      "NetworkBackup": Schema.object([
        "format": ["type": "integer", "const": 1, "description": "The file's format number. It rises when a reader of an older number could misread the file; a key a reader doesn't know is ignored."],
        "createdAt": ["type": "string", "format": "date-time", "description": "When the backup was taken, to the second, in UTC."],
        "source": Schema.string(enum: ["modem", "hubPro", "service"], description: "What the backup was taken from. The service's backup is `service`."),
        "modem": Schema.ref("BackupModem"),
        "devices": Schema.array(of: Schema.ref("BackupDevice")),
        "notificationRules": Schema.array(of: Schema.ref("NotificationRule")),
        "routes": Schema.array(of: Schema.ref("Route")),
        "schedules": Schema.array(of: Schema.ref("Schedule")),
        "checksum": Schema.string(pattern: "^sha256:[0-9a-f]{64}$", description: "The SHA-256 of the document's JSON without this key, written with sorted keys and no spacing.")
      ], required: ["format", "createdAt", "source", "devices", "checksum"], description: "A home's Insteon network in one document. It holds no password, client token or Hub address."),
      "BackupModem": Schema.object([
        "address": address,
        "identity": Schema.ref("BackupIdentity"),
        "allLinkDatabase": Schema.array(of: Schema.ref("BackupRecord")),
        "unreadable": Schema.ref("BackupUnreadable")
      ], required: ["address"], description: "The modem. It has `allLinkDatabase` or `unreadable`, and not both."),
      "BackupDevice": Schema.object([
        "address": address,
        "name": Schema.string(description: "A name the Hub gave the device."),
        "type": Schema.string(description: "What the device is."),
        "identity": Schema.ref("BackupIdentity"),
        "engine": Schema.string(enum: ["i1", "i2", "i2cs"], description: "The engine the device runs."),
        "allLinkDatabase": Schema.ref("BackupDatabase"),
        "unreadable": Schema.ref("BackupUnreadable")
      ], required: ["address"], description: "A device. It has `allLinkDatabase` or `unreadable`, and not both."),
      "BackupIdentity": Schema.object([
        "category": Schema.string(pattern: "^0x[0-9A-F]{2}$", description: "The category."),
        "subcategory": Schema.string(pattern: "^0x[0-9A-F]{2}$", description: "The subcategory."),
        "firmwareVersion": Schema.string(pattern: "^0x[0-9A-F]{2}$", description: "The firmware version, if it is known.")
      ], required: ["category", "subcategory"]),
      "BackupDatabase": Schema.object([
        "delta": Schema.integer(minimum: 0, maximum: 255, description: "The delta the device reported when its database was read."),
        "records": Schema.array(of: Schema.ref("BackupRecord"))
      ], required: ["delta", "records"], description: "A device's ALL-Link database in the device's order, ending with the record that marks its end when the whole database was read."),
      "BackupRecord": Schema.object([
        "state": Schema.string(enum: ["inUse", "free", "end"], description: "Whether the record holds a link, is free, or marks the end of the database."),
        "role": Schema.string(enum: ["controller", "responder"], description: "Whether the database's owner controls the group or responds to it."),
        "group": Schema.integer(minimum: 0, maximum: 255, description: "The owner's own group in a controller record, and the other device's in a responder record."),
        "address": address,
        "data": Schema.string(pattern: "^[0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2}$", description: "The record's three data bytes."),
        "memory": Schema.string(pattern: "^0x[0-9A-F]{4}$", description: "Where the record is in a device's database. A record of the modem's has none.")
      ], required: ["state", "role", "group", "address", "data"]),
      "BackupUnreadable": Schema.object([
        "reason": Schema.string(enum: ["noAnswer", "rejectedModem", "damagedRecords", "notCached", "unavailableFromSource", "modemStoppedEchoing", "hubStoppedAnswering", "failed", "incomplete"], description: "Why there is no ALL-Link database."),
        "detail": Schema.string(description: "A short note that holds no address or credential.")
      ], required: ["reason"]),
      "ScheduleAction": Schema.object([
        "device": address,
        "action": Schema.string(enum: ScheduleActionName.allCases.map(\.rawValue)),
        "levelPercent": Schema.integer(minimum: 0, maximum: 100, description: "Only for `on`, and only for a device that dims.")
      ], required: ["device", "action"], description: "A switching command, the same as a client's command on a device's main group."),
      "ScheduleTime": [
        "oneOf": [
          Schema.object(["kind": Schema.constant(ScheduleTimeKind.clock.rawValue), "hour": Schema.integer(minimum: 0, maximum: 23), "minute": Schema.integer(minimum: 0, maximum: 59)], required: ["kind", "hour", "minute"]),
          Schema.object(["kind": Schema.constant(ScheduleTimeKind.sunrise.rawValue), "offsetSeconds": Schema.integer(minimum: -ServiceSchedule.longestOffsetSeconds, maximum: ServiceSchedule.longestOffsetSeconds, description: "Seconds after sunrise, negative for before. Defaults to 0.")], required: ["kind"]),
          Schema.object(["kind": Schema.constant(ScheduleTimeKind.sunset.rawValue), "offsetSeconds": Schema.integer(minimum: -ServiceSchedule.longestOffsetSeconds, maximum: ServiceSchedule.longestOffsetSeconds, description: "Seconds after sunset, negative for before. Defaults to 0.")], required: ["kind"])
        ],
        "description": "A clock time is wall-clock time in the service's time zone. Sunrise and sunset are worked out for the service's location and need it."
      ],
      "ScheduleWhen": Schema.object([
        "time": Schema.ref("ScheduleTime"),
        "weekdays": ["type": "array", "items": Schema.string(enum: WeekdayName.allCases.map(\.rawValue)), "uniqueItems": true, "description": "The days the schedule runs on, without repeats. Defaults to every day."]
      ], required: ["time"]),
      "Schedule": Schema.object([
        "id": Schema.string(description: "The schedule's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters."),
        "name": Schema.string(description: "1 through 64 characters, without control characters."),
        "enabled": Schema.boolean,
        "when": Schema.ref("ScheduleWhen"),
        "action": Schema.ref("ScheduleAction"),
        "catchUp": ["type": "boolean", "description": "Whether a run missed while the service was stopped still happens when it is less than 15 minutes late. Off, a missed run is skipped."],
        "nextRun": Schema.nullable(["type": "string", "format": "date-time", "description": "When the schedule runs next. Null for a disabled schedule or one with no run to come."])
      ], required: ["id", "name", "enabled", "when", "action", "catchUp"]),
      "SceneList": Schema.object([
        "version": version,
        "scenes": Schema.array(of: Schema.ref("Scene")),
        "looseHalfLinks": Schema.array(of: Schema.ref("HalfLink")),
        "unreadable": Schema.array(of: Schema.ref("UnreadableDevice")),
        "unlisted": Schema.array(of: address),
        "modemUnread": Schema.boolean,
        "undescribedMembers": Schema.array(of: address),
        "whole": Schema.boolean
      ], required: ["version", "scenes", "looseHalfLinks", "unreadable", "unlisted", "modemUnread", "undescribedMembers", "whole"]),
      "UnreadableDevice": Schema.object([
        "address": address,
        "reason": Schema.string(enum: ["noAnswer", "rejectedModem", "damagedRecords", "notCached", "unavailableFromSource", "modemStoppedEchoing", "hubStoppedAnswering", "failed", "incomplete"], description: "Why the device's ALL-Link database was not read. `notCached` is a device no refresh has tried.")
      ], required: ["address", "reason"], description: "A device whose ALL-Link database the service does not hold."),
      "Scene": Schema.object([
        "number": Schema.integer(minimum: 0, maximum: 255),
        "controller": Schema.string(description: "`modem`, or the address of the device that controls the scene."),
        "writable": Schema.boolean,
        "members": Schema.array(of: Schema.ref("SceneMember")),
        "halfLinks": Schema.array(of: Schema.ref("HalfLink"))
      ], required: ["number", "controller", "writable", "members", "halfLinks"]),
      "SceneMember": Schema.object([
        "address": address,
        "data": Schema.array(of: Schema.integer(minimum: 0, maximum: 255)),
        "described": Schema.boolean,
        "bytes": Schema.array(of: Schema.ref("LinkDataByte"))
      ], required: ["address", "data", "described", "bytes"]),
      "LinkDataByte": Schema.object([
        "position": Schema.integer(minimum: 1, maximum: 3),
        "name": Schema.string(),
        "label": Schema.nullable(Schema.string()),
        "value": Schema.integer(minimum: 0, maximum: 255),
        "valueName": Schema.nullable(Schema.string()),
        "perGroup": Schema.boolean,
        "verification": Schema.string(description: "How sure the Insteon device catalog is of the byte: `observed`, `documented`, `inferred` or `conflicting`.")
      ], required: ["position", "name", "value", "perGroup", "verification"]),
      "HalfLink": Schema.object([
        "endpoint": Schema.string(description: "`modem`, or the address of the device whose database holds the record."),
        "group": Schema.integer(minimum: 0, maximum: 255),
        "address": address,
        "role": Schema.string(enum: ["controller", "responder"]),
        "data": Schema.array(of: Schema.integer(minimum: 0, maximum: 255))
      ], required: ["endpoint", "group", "address", "role", "data"]),
      "ScheduleList": Schema.object(["version": version, "schedules": Schema.array(of: Schema.ref("Schedule"))], required: ["version", "schedules"]),
      "ScheduleStored": Schema.object(["version": version, "schedule": Schema.ref("Schedule")], required: ["version", "schedule"]),
      "ScheduleRequest": Schema.object([
        "name": Schema.string(description: "1 through 64 characters, without control characters."),
        "enabled": Schema.boolean,
        "when": Schema.ref("ScheduleWhen"),
        "action": Schema.ref("ScheduleAction"),
        "catchUp": Schema.boolean
      ], required: ["name", "when", "action"], description: "A schedule without its identifier. Defaults: `enabled` true, `catchUp` false."),
      "Timer": Schema.object([
        "id": Schema.string(description: "The timer's identifier."),
        "name": Schema.string(description: "1 through 64 characters, without control characters."),
        "delaySeconds": Schema.integer(minimum: 1, maximum: ServiceTimer.longestDelaySeconds),
        "action": Schema.ref("ScheduleAction"),
        "dueAt": ["type": "string", "format": "date-time", "description": "When the timer fires by the service's clock. A change of the clock moves this time, not the moment the timer fires."],
        "remainingSeconds": Schema.integer(minimum: 0, description: "The seconds left, counted in elapsed time.")
      ], required: ["id", "name", "delaySeconds", "action", "dueAt", "remainingSeconds"]),
      "TimerList": Schema.object(["version": version, "timers": Schema.array(of: Schema.ref("Timer"))], required: ["version", "timers"]),
      "TimerStored": Schema.object(["version": version, "timer": Schema.ref("Timer")], required: ["version", "timer"]),
      "TimerRequest": Schema.object([
        "name": Schema.string(description: "1 through 64 characters, without control characters."),
        "delaySeconds": Schema.integer(minimum: 1, maximum: ServiceTimer.longestDelaySeconds),
        "action": Schema.ref("ScheduleAction")
      ], required: ["name", "delaySeconds", "action"], description: "A timer without its identifier."),
      "Route": Schema.object([
        "kind": Schema.string(description: "The transport's identifier."),
        "ticket": Schema.string(description: "What the transport needs to reach the service. Only that transport reads it.")
      ], required: ["kind", "ticket"], description: "A route a transport registered. A pairing document lists it after the `lan` route."),
      "RouteList": Schema.object(["version": version, "routes": Schema.array(of: Schema.ref("Route"))], required: ["version", "routes"]),
      "RouteStored": Schema.object(["version": version, "route": Schema.ref("Route")], required: ["version", "route"]),
      "RouteRequest": Schema.object([
        "ticket": Schema.string(pattern: RouteStore.ticketPattern, description: "1 through \(RouteStore.longestTicket) printable ASCII characters, without spaces.")
      ], required: ["ticket"], description: "A route without its kind, which the path gives."),
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
          "name": Schema.string(description: "The network's name, for a client to show."),
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
