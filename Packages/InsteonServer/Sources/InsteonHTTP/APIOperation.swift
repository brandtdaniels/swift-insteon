import HTTPTypes

/// One route the server answers. This list is the single description of the HTTP surface: the router
/// registers its routes from it, and `/api/v1/openapi.json` is generated from it, so a route can't
/// exist without being described or be described without existing.
enum APIOperation: String, CaseIterable, Sendable {
  case listDevices, health, executeCommand, streamEvents, openAPI
  case listClients, createClient, revokeClient, createPairing
  case listNotificationRules, putNotificationRule, deleteNotificationRule
  case listRoutes, putRoute, deleteRoute
  case getBackup
  case listScenes, refreshScenes, runScene, planSceneMembership, applySceneMembership
  case listSchedules, putSchedule, deleteSchedule
  case listTimers, putTimer, deleteTimer
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
    case .listDevices, .health, .executeCommand, .streamEvents, .openAPI, .listClients, .createClient, .revokeClient, .createPairing, .listNotificationRules, .putNotificationRule, .deleteNotificationRule, .listRoutes, .putRoute, .deleteRoute, .listSchedules, .putSchedule, .deleteSchedule, .listTimers, .putTimer, .deleteTimer, .getBackup, .listScenes, .refreshScenes, .runScene, .planSceneMembership, .applySceneMembership: true
    case .browserIndex, .browserControls, .browserCard, .browserCommand: false
    }
  }

  var method: HTTPRequest.Method {
    switch self {
    case .executeCommand, .browserCommand, .createClient, .createPairing, .refreshScenes, .runScene, .planSceneMembership, .applySceneMembership: .post
    case .revokeClient, .deleteNotificationRule, .deleteRoute, .deleteSchedule, .deleteTimer: .delete
    case .putNotificationRule, .putRoute, .putSchedule, .putTimer: .put
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
    case .getBackup: "/api/v1/backup"
    case .listScenes: "/api/v1/scenes"
    case .refreshScenes: "/api/v1/scenes/refresh"
    case .runScene: "/api/v1/scenes/{number}/commands"
    case .planSceneMembership: "/api/v1/scenes/{number}/plans"
    case .applySceneMembership: "/api/v1/scenes/{number}/plans/{id}/apply"
    case .listSchedules: "/api/v1/schedules"
    case .putSchedule, .deleteSchedule: "/api/v1/schedules/{id}"
    case .listTimers: "/api/v1/timers"
    case .putTimer, .deleteTimer: "/api/v1/timers/{id}"
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
    case .getBackup: "Read a backup of the cached network"
    case .listScenes: "List the scenes of the network"
    case .refreshScenes: "Read the ALL-Link databases from the hardware and list the scenes"
    case .runScene: "Turn a scene the modem controls on or off"
    case .planSceneMembership: "Plan adding and removing the members of a scene the modem controls"
    case .applySceneMembership: "Write a plan's ALL-Link records, with consent that names the plan"
    case .listSchedules: "List the schedules and when each runs next"
    case .putSchedule: "Store a schedule"
    case .deleteSchedule: "Remove a schedule"
    case .listTimers: "List the timers and when each fires"
    case .putTimer: "Start a timer"
    case .deleteTimer: "Cancel a timer"
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
    case .getBackup: "The same document format `insteon backup` writes: the modem's address and ALL-Link database, each device's ALL-Link database, names and identities, the notification rules, the routes and the schedules (timers are left out). It answers from the cache and sends nothing to hardware, so a device the service holds no copy of is listed with the reason `notCached`. It holds no password, client token or Hub address. Needs the `admin` scope."
    case .listScenes: "A scene is a group of the modem or of a device with the devices that respond to it; the modem's are `writable`, a device's are read only. Each member has its three link data bytes. It answers from the ALL-Link databases the service has cached and sends nothing to hardware. `whole` is false while a device's database is not held (`unreadable`, each with its `reason`), a record names a device with no database (`unlisted`), the modem's database is not held (`modemUnread`) or a record has no other half (`halfLinks`, `looseHalfLinks`). Needs the `read` scope."
    case .runScene: "Sends the scene's ALL-Link group one Light On at full level or one Light Off through the modem, then waits for the modem's ALL-Link cleanups, so each member recalls the on-level or off its own link data holds. The scene is a group from 1 through 254 that the listing from `GET /api/v1/scenes` shows as `writable`; a group a device controls is `unknownScene`, as is a number the service has not read (`POST /api/v1/scenes/refresh` reads them), and a scene with no members is `sceneEmpty`. Nothing is sent in those cases. The receipt's `outcome` is `acknowledged` when the modem acknowledged sending the group command. `acknowledged` lists the members that acknowledged their cleanup and `unacknowledged` those that did not, who may still have acted; a modem that passes no per-member acknowledgment up, as a Hub 2 does not, leaves `acknowledged` empty, and `isComplete` is the modem's own report that it reached every member. Empty never means that no member acted. The command is sent at most once and never repeated by the service. The service does not read the members afterward, so `GET /api/v1/devices` keeps the levels it held until a device is read or reports. With an `Idempotency-Key`, a repeat of the same run returns the recorded answer with `Idempotent-Replay: true` and sends nothing. `sent` in an error says whether the command may have reached the members. It takes the service's one admission gate, so another operation is refused as `busy` and nothing is queued. A `scene` event follows on the event stream. Needs the `control` scope."
    case .planSceneMembership: "Answers what adding and removing members would write, without writing or sending anything: the service plans from the ALL-Link databases it has cached and the Insteon device catalog, and a database it does not hold is a refusal that says to refresh the scenes. The plan lists its `steps` in the order they would be made, each naming the record written or deleted and whether it is the modem's or a device's, with the three data bytes of a member's record, and `devices` says whether each device takes a remote write. `warnings` and `refusals` carry typed codes; a plan with a refusal cannot be applied and has no `consent`. A member already in the scene with the same record gets no step. One with another on-level or ramp rate is listed as an update in place and refused as `notYetSupported`, because rewriting a record in use has not been tried on hardware. The scene is a group from 1 through 254; a number no controller uses is a scene to create, and a group a device controls is `unknownScene`. The service keeps a plan that can be applied in memory for five minutes, named by `planId`. `consent` is what applying the plan will need, the same consent that applying a database link plan takes. Apply the plan with `POST /api/v1/scenes/{number}/plans/{id}/apply`; this route writes nothing. Needs the `admin` scope, and consent is never implied by it."
    case .applySceneMembership: "Writes the ALL-Link records of a plan from `POST /api/v1/scenes/{number}/plans`, in the plan's order, and answers each step's outcome. The body is `{\"consent\": {\"writeLinkRecords\": true, \"readFingerprint\": \"<the plan's consent.readFingerprint>\"}}` and nothing else: there is no `force`, because a plan never overwrites a record in use. Consent is never implied by the `admin` scope, so a missing or false `writeLinkRecords`, or no fingerprint, is `consentRequired`, and a fingerprint of another plan is `consentMismatch`; neither sends anything. A plan the service does not hold for that scene is `unknownPlan`, one older than five minutes is `planExpired`, and one with a refusal or no steps is `planNotApplicable`. A plan is used once: the same plan again is `planAlreadyApplied`, and a repeat with the same `Idempotency-Key` returns the recorded answer and writes nothing. The service takes its one admission gate (`busy`), reads the modem's database and each device's from the hardware, and writes nothing (`planStale`) if any differs from what the plan was made from. It then makes each step through the same path as the command line's database writer: a record in use is never overwritten, the end of a device's database is marked one slot below before its slot is written, each write is read back and made once more if it reads back differently, and the steps stop after the first that fails. Last it reads both databases again and compares them with what the steps made should have left, and it reads the databases it changed into its cache (`cacheReload` says whether that worked). A step's `outcome` is `written`, `writtenOnRetry`, `unverifiable` (an i2CS device that rejects the modem once its last record of the modem is gone), `notWritten`, `rejected`, `unanswered` or `notReached`. When every step was made and both databases read back as planned the answer is 200 with `outcome` `applied`. When every step was made and no record differs, but reading the databases again did not finish (a device did not answer), the answer is 200 with `outcome` `appliedUnverified`, `isComplete` false and a `message` that says to refresh the scenes and check; it is recorded for an `Idempotency-Key` like any apply. When any step failed or was not reached, or a record read back differently, the answer is 502 `outcomeUnknown` with `sent` true and the same body, so a client sees exactly which records were written and which were not. Nothing is rolled back and nothing is repeated beyond the one retry; a client plans again from a fresh read. Either answer publishes a `sceneMembership` event with `scene`, `source`, `outcome`, `stepsMade`, `stepsNotMade` and `firedAt`. Needs the `admin` scope. A Hub Pro takes no database write: `databasesUnavailable`."
    case .refreshScenes: "Reads the ALL-Link database of the modem and of each device from the hardware, one request at a time, and answers with the scenes as `GET /api/v1/scenes` lists them after the read. It only reads: nothing is written to the modem or to a device. A device that does not answer is listed as `unreadable` and the refresh still succeeds. A read takes the service's one admission gate for as long as it lasts, so another operation is refused as `busy` and nothing is queued. A Hub Pro does not give out its ALL-Link databases, so it answers `databasesUnavailable`. Needs the `control` scope."
    case .listSchedules: "The schedules in the order they were added, each with the time it runs next in the service's time zone. Needs the `read` scope."
    case .putSchedule: "Adds the schedule, or replaces the schedule with that identifier, which keeps nothing of the old schedule's last run. It takes effect at once. A clock time is wall-clock time in the service's time zone, so it follows daylight saving time: a time the clocks skip runs once, when the skipped span ends, and a time that happens twice runs at its first occurrence. A run less than a minute late happens; a later one is skipped, unless `catchUp` is true and it is less than 15 minutes late. Each run publishes a `schedule` event on `/api/v1/events`. Needs the `admin` scope."
    case .deleteSchedule: "Removes the schedule, which stops at once. Needs the `admin` scope."
    case .listTimers: "The timers that haven't fired, in the order they were started. Needs the `read` scope."
    case .putTimer: "Starts the timer, or restarts the timer with that identifier. It counts elapsed time, so a change of the clock neither lengthens nor shortens it, fires once, and is then removed. A restart keeps the time the timer had left. Its run publishes a `schedule` event with `source` `timer`. Needs the `admin` scope."
    case .deleteTimer: "Cancels the timer. Needs the `admin` scope."
    case .browserIndex, .browserControls, .browserCard, .browserCommand: "Part of the browser page, not of the versioned API contract."
    }
  }

  private static let addressParameter = Parameter(name: "address", location: "path", required: true, schema: Schema.string(description: "A device address such as 1A.2B.3C."), description: "The device's Insteon address.")

  private static let sceneParameter = Parameter(name: "number", location: "path", required: true, schema: Schema.integer(minimum: 1, maximum: 254), description: "The scene's ALL-Link group number, from 1 through 254.")
  private static let clientParameter = Parameter(name: "id", location: "path", required: true, schema: Schema.string(description: "A client's identifier."), description: "The client's identifier, from the list or the creation response.")
  private static let ruleParameter = Parameter(name: "id", location: "path", required: true, schema: Schema.string(description: "A rule's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters."), description: "The rule's identifier. A client chooses it.")
  private static let scheduleParameter = Parameter(name: "id", location: "path", required: true, schema: Schema.string(description: "A schedule's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters."), description: "The schedule's identifier. A client chooses it.")
  private static let timerParameter = Parameter(name: "id", location: "path", required: true, schema: Schema.string(description: "A timer's identifier: letters, digits, `-`, `_` and `.`, at most 64 characters."), description: "The timer's identifier. A client chooses it.")
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
    case .runScene:
      [
        Self.sceneParameter,
        Parameter(name: "X-Insteon-Request", location: "header", required: true, schema: Schema.constant("1"), description: "Marks an explicit API request, so a browser page can't run a scene by accident."),
        Parameter(name: "Idempotency-Key", location: "header", required: false, schema: Schema.string(pattern: IdempotencyKey.pattern), description: "A token the client picks, 1 through 128 characters. A repeat with the same key and command returns the recorded answer.")
      ]
    case .planSceneMembership: [Self.sceneParameter, Self.markerParameter]
    case .applySceneMembership:
      [
        Self.sceneParameter,
        Parameter(name: "id", location: "path", required: true, schema: Schema.string(pattern: "^sha256:[0-9a-f]{64}$", description: "A plan's identifier."), description: "The plan's `planId` from the plan route."),
        Self.markerParameter,
        Parameter(name: "Idempotency-Key", location: "header", required: false, schema: Schema.string(pattern: IdempotencyKey.pattern), description: "A token the client picks, 1 through 128 characters. A repeat with the same key and consent returns the recorded answer and writes nothing.")
      ]
    case .createClient, .refreshScenes: [Self.markerParameter]
    case .revokeClient, .createPairing: [Self.clientParameter, Self.markerParameter]
    case .putNotificationRule, .deleteNotificationRule: [Self.ruleParameter, Self.markerParameter]
    case .putRoute, .deleteRoute: [Self.routeParameter, Self.markerParameter]
    case .putSchedule, .deleteSchedule: [Self.scheduleParameter, Self.markerParameter]
    case .putTimer, .deleteTimer: [Self.timerParameter, Self.markerParameter]
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
    case .putSchedule: Body(contentType: "application/json", schema: Schema.ref("ScheduleRequest"), description: "The schedule without its identifier, which the path gives. Unknown fields are refused. The body is at most 8 KiB.")
    case .putTimer: Body(contentType: "application/json", schema: Schema.ref("TimerRequest"), description: "The timer without its identifier, which the path gives. Unknown fields are refused. The body is at most 8 KiB.")
    case .planSceneMembership: Body(contentType: "application/json", schema: Schema.ref("SceneMembershipRequest"), description: "The devices to add and to remove. Unknown fields are refused, and so is an empty change. A device named twice for the same group, or in both lists, is refused in the plan. The body is at most 8 KiB.")
    case .applySceneMembership: Body(contentType: "application/json", schema: Schema.ref("SceneMembershipApplyRequest"), description: "The consent. Unknown fields, including `force`, are refused. The body is at most 8 KiB.")
    case .runScene: Body(contentType: "application/json", schema: Schema.ref("SceneCommand"), description: "The command: `action` is `on` or `off`. Unknown fields, including a level, are refused. The body is at most 8 KiB.")
    case .putRoute: Body(contentType: "application/json", schema: Schema.ref("RouteRequest"), description: "The route's ticket. Unknown fields are refused. The body is at most 8 KiB.")
    case .browserCommand: Body(contentType: "application/x-www-form-urlencoded", schema: Schema.string(), description: "The page's form: `action`, optional `levelPercent`, and the page's `formKey`.")
    default: nil
    }
  }

  /// The weakest scope a credential needs for the operation. The gateway password is `admin`, and a
  /// browser route takes only the password.
  var requiredScope: ClientScope {
    switch self {
    case .listDevices, .health, .streamEvents, .openAPI, .listNotificationRules, .listRoutes, .listSchedules, .listTimers, .listScenes: .read
    case .executeCommand, .refreshScenes, .runScene: .control
    case .listClients, .createClient, .revokeClient, .createPairing, .putNotificationRule, .deleteNotificationRule, .putRoute, .deleteRoute, .putSchedule, .deleteSchedule, .putTimer, .deleteTimer, .getBackup, .planSceneMembership, .applySceneMembership: .admin
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
    case .listSchedules, .listTimers: codes += [.schedulesNotSaved]
    case .putSchedule: codes += [.invalidSchedule, .unknownDevice, .unsupportedControl, .locationNotConfigured, .timeZoneUnavailable, .scheduleLimitReached, .schedulesNotSaved, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected]
    case .putTimer: codes += [.invalidTimer, .unknownDevice, .unsupportedControl, .timerLimitReached, .schedulesNotSaved, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected]
    case .deleteSchedule: codes += [.unknownSchedule, .schedulesNotSaved, .apiMarkerMissing]
    case .deleteTimer: codes += [.unknownTimer, .schedulesNotSaved, .apiMarkerMissing]
    case .listRoutes: codes += [.routeRegistrationsNotSaved]
    case .putRoute: codes += [.invalidRouteRegistration, .routeRegistrationLimitReached, .routeRegistrationsNotSaved, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected]
    case .deleteRoute: codes += [.unknownRouteRegistration, .routeRegistrationsNotSaved, .apiMarkerMissing]
    case .runScene: codes += [.invalidScene, .invalidCommand, .invalidIdempotencyKey, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected, .unknownScene, .sceneEmpty, .idempotencyKeyReused, .busy, .modemUnavailable, .modemRejected, .databasesUnavailable, .canceled, .outcomeUnknown]
    case .planSceneMembership: codes += [.invalidScene, .invalidMembership, .invalidAddress, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .requestRejected, .unknownScene, .databasesUnavailable, .canceled]
    case .applySceneMembership: codes += [.invalidScene, .invalidCommand, .invalidBody, .invalidIdempotencyKey, .apiMarkerMissing, .unsupportedMediaType, .bodyTooLarge, .unknownPlan, .planExpired, .planAlreadyApplied, .planNotApplicable, .planStale, .consentRequired, .consentMismatch, .idempotencyKeyReused, .busy, .modemUnavailable, .modemRejected, .databasesUnavailable, .canceled, .deviceNotAnswering, .deviceRejected, .notLinked, .outcomeUnknown]
    case .refreshScenes: codes += [.apiMarkerMissing, .busy, .modemUnavailable, .modemRejected, .databasesUnavailable, .canceled, .deviceNotAnswering]
    case .getBackup: codes += [.notificationRulesNotSaved, .routeRegistrationsNotSaved, .schedulesNotSaved]
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
    case .listSchedules: [Reply(status: 200, description: "The schedules.", contentType: "application/json", schema: Schema.ref("ScheduleList"), headers: [:])]
    case .putSchedule: [Reply(status: 200, description: "The stored schedule, with its next run.", contentType: "application/json", schema: Schema.ref("ScheduleStored"), headers: [:])]
    case .deleteSchedule: [Reply(status: 204, description: "The schedule is removed.", contentType: nil, schema: nil, headers: [:])]
    case .listTimers: [Reply(status: 200, description: "The timers.", contentType: "application/json", schema: Schema.ref("TimerList"), headers: [:])]
    case .putTimer: [Reply(status: 200, description: "The started timer.", contentType: "application/json", schema: Schema.ref("TimerStored"), headers: [:])]
    case .deleteTimer: [Reply(status: 204, description: "The timer is canceled.", contentType: nil, schema: nil, headers: [:])]
    case .listRoutes: [Reply(status: 200, description: "The routes.", contentType: "application/json", schema: Schema.ref("RouteList"), headers: [:])]
    case .putRoute: [Reply(status: 200, description: "The stored route.", contentType: "application/json", schema: Schema.ref("RouteStored"), headers: [:])]
    case .deleteRoute: [Reply(status: 204, description: "The route is removed.", contentType: nil, schema: nil, headers: [:])]
    case .listScenes: [Reply(status: 200, description: "The scenes.", contentType: "application/json", schema: Schema.ref("SceneList"), headers: [:])]
    case .refreshScenes: [Reply(status: 200, description: "The scenes, read from the hardware.", contentType: "application/json", schema: Schema.ref("SceneList"), headers: [:])]
    case .runScene: [Reply(status: 200, description: "The scene's receipt.", contentType: "application/json", schema: Schema.ref("SceneReceipt"), headers: ["Idempotent-Replay": ["$ref": "#/components/headers/IdempotentReplay"]])]
    case .planSceneMembership: [Reply(status: 200, description: "The plan. Nothing was written or sent.", contentType: "application/json", schema: Schema.ref("SceneMembershipPlan"), headers: [:])]
    case .applySceneMembership: [Reply(status: 200, description: "Every step was made, and both databases read back as planned (`applied`) or reading them again did not finish (`appliedUnverified`).", contentType: "application/json", schema: Schema.ref("SceneMembershipApplication"), headers: ["Idempotent-Replay": ["$ref": "#/components/headers/IdempotentReplay"]])]
    case .getBackup: [Reply(status: 200, description: "The backup, as `insteon backup` writes it.", contentType: "application/json", schema: Schema.ref("NetworkBackup"), headers: [:])]
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
      if self == .executeCommand || self == .runScene || self == .applySceneMembership { headers["Idempotent-Replay"] = ["$ref": "#/components/headers/IdempotentReplay"] }
      // A plan applied in part answers 502 with the steps, so a client sees what was and was not written.
      let schema: JSONValue? = isAPI ? Schema.ref(self == .applySceneMembership && status == 502 ? "SceneMembershipApplication" : "Error") : nil
      replies.append(Reply(
        status: status,
        description: "Failure: " + codes.map(\.rawValue).joined(separator: ", ") + ".",
        contentType: isAPI ? "application/json" : "text/plain",
        schema: schema,
        headers: headers
      ))
    }
    return replies
  }
}
