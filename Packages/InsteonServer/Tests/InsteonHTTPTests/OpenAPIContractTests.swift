import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonScheduling
import InsteonService
import Testing
@testable import InsteonHTTP

/// The served description is checked against the router and the types it describes, never against a
/// frozen copy of itself: expectations come from the route table, the error vocabulary and the
/// real response types.
@Suite(.timeLimit(.minutes(1)))
struct OpenAPIContractTests {
  let password = String(repeating: "p", count: 40)
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  private var authorization: HTTPFields { [.authorization: "Basic " + Data(("insteon:" + password).utf8).base64EncodedString()] }

  private func application(_ service: FakeService = FakeService()) throws -> Application<RouterResponder<BasicRequestContext>> {
    Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
  }

  private func fetch() async throws -> (bytes: Data, document: [String: Any]) {
    let app = try application()
    return try await app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/openapi.json", method: .get, headers: authorization)
      #expect(response.status == .ok)
      #expect(response.headers[.contentType] == "application/json")
      let bytes = Data(response.body.readableBytesView)
      return (bytes, try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any]))
    }
  }

  /// Every (method, path) the document describes.
  private func described(_ document: [String: Any]) -> [(method: String, path: String, operation: [String: Any])] {
    let paths = document["paths"] as? [String: [String: Any]] ?? [:]
    return paths.flatMap { path, item in
      item.compactMap { method, operation in (operation as? [String: Any]).map { (method.uppercased(), path, $0) } }
    }.sorted { ($0.path, $0.method) < ($1.path, $1.method) }
  }

  // MARK: One list of routes

  @Test func theRoutesRegisteredAreExactlyTheRoutesDescribed() async throws {
    let built = makeRegisteredRouter(service: FakeService(), authentication: try HTTPAuthentication(password: password), logger: LogCapture().logger, now: { Date() })
    let registered = Set(built.registered.map { "\($0.method.rawValue) \($0.path)" })
    let (_, document) = try await fetch()
    let documented = Set(described(document).map { "\($0.method) \($0.path)" })
    #expect(registered == documented)
    #expect(built.registered.count == registered.count, "an operation is registered twice")
    #expect(Set(built.registered) == Set(APIOperation.allCases))
  }

  @Test func everyDescribedRouteIsServedAndAnUndescribedOneIsNot() async throws {
    let (_, document) = try await fetch()
    let app = try application()
    let routes = described(document).map { (method: $0.method, path: $0.path) }
    try await app.test(.router) { client in
      for route in routes {
        let uri = route.path.replacingOccurrences(of: "{address}", with: "1A.2B.3C").replacingOccurrences(of: "{id}", with: "0123456789abcdef")
        let method = HTTPRequest.Method(rawValue: route.method)!
        let response = try await client.execute(uri: uri, method: method, headers: authorization)
        #expect(String(buffer: response.body) != "No such route.", "\(route.method) \(route.path) is described but not served")
        #expect(!(response.status == .notFound && String(buffer: response.body).contains("routeNotFound")), "\(route.method) \(route.path) is described but not served")
      }
      let undescribed = try await client.execute(uri: "/api/v1/undescribed", method: .get, headers: authorization)
      #expect(undescribed.status == .notFound)
      #expect(String(buffer: undescribed.body).contains("routeNotFound"))
    }
  }

  // MARK: The error vocabulary

  @Test func everyErrorCodeIsDescribedWithItsStatusAndSent() async throws {
    let (_, document) = try await fetch()
    let components = try #require(document["components"] as? [String: Any])
    let schema = try #require((components["schemas"] as? [String: Any])?["ErrorCode"] as? [String: Any])
    let listed = try #require(schema["enum"] as? [String])
    #expect(listed == APIErrorCode.allCases.map(\.rawValue))
    let entries = try #require(schema["x-codes"] as? [[String: Any]])
    for code in APIErrorCode.allCases {
      let entry = try #require(entries.first { $0["code"] as? String == code.rawValue })
      #expect(entry["status"] as? Int == Int(code.status.code))
      #expect(entry["sent"] as? Bool == code.sent)
      #expect((entry["message"] as? String)?.isEmpty == false)
    }
  }

  @Test func everyErrorCodeIsListedUnderAnOperationThatCanAnswerIt() async throws {
    let (_, document) = try await fetch()
    let text = described(document).flatMap { route -> [String] in
      (route.operation["responses"] as? [String: [String: Any]] ?? [:]).values.compactMap { $0["description"] as? String }
    }.joined(separator: "\n") + "\n" + (((document["info"] as? [String: Any])?["description"] as? String) ?? "")
    for code in APIErrorCode.allCases {
      #expect(text.contains(code.rawValue), "\(code.rawValue) is under no operation")
    }
  }

  @Test func theStatusADescribedFailureAnswersWithIsADocumentedStatusOfTheOperation() async throws {
    let (_, document) = try await fetch()
    for route in described(document) where route.path.hasPrefix("/api/") {
      let statuses = Set((route.operation["responses"] as? [String: Any] ?? [:]).keys)
      for code in (APIOperation.allCases.first { $0.path == route.path && $0.method.rawValue == route.method })?.errorCodes ?? [] {
        #expect(statuses.contains(String(code.status.code)), "\(route.path) lists \(code.rawValue) without a \(code.status.code) response")
      }
    }
  }

  // MARK: Structure of OpenAPI 3.1

  @Test func theDocumentIsStructurallyOpenAPI31() async throws {
    let (_, document) = try await fetch()
    #expect(document["openapi"] as? String == "3.1.0")
    let info = try #require(document["info"] as? [String: Any])
    #expect((info["title"] as? String)?.isEmpty == false)
    #expect((info["version"] as? String)?.isEmpty == false)
    let paths = try #require(document["paths"] as? [String: Any])
    #expect(!paths.isEmpty)

    var operationIDs: [String] = []
    for route in described(document) {
      #expect(route.path.hasPrefix("/"))
      let id = try #require(route.operation["operationId"] as? String, "\(route.method) \(route.path) has no operationId")
      operationIDs.append(id)
      let responses = try #require(route.operation["responses"] as? [String: [String: Any]])
      #expect(!responses.isEmpty)
      for (status, response) in responses {
        #expect(Int(status).map { (100...599).contains($0) } == true, "\(status) isn't a status")
        #expect((response["description"] as? String)?.isEmpty == false)
      }
      // The parameters declared are the path's variables, no more and no fewer.
      let parameters = route.operation["parameters"] as? [[String: Any]] ?? []
      let declared = Set(parameters.filter { $0["in"] as? String == "path" }.compactMap { $0["name"] as? String })
      let template = Set(route.path.split(separator: "/").compactMap { $0.hasPrefix("{") ? String($0.dropFirst().dropLast()) : nil })
      #expect(declared == template, "\(route.path)")
      for parameter in parameters {
        #expect(["path", "query", "header"].contains(parameter["in"] as? String ?? ""))
        #expect(parameter["name"] is String)
        if parameter["in"] as? String == "path" { #expect(parameter["required"] as? Bool == true) }
        #expect(parameter["schema"] != nil)
      }
    }
    #expect(Set(operationIDs).count == operationIDs.count, "operationIds repeat")
    #expect(Set(operationIDs) == Set(APIOperation.allCases.map(\.rawValue)))

    let security = try #require(document["security"] as? [[String: Any]])
    let schemes = try #require((document["components"] as? [String: Any])?["securitySchemes"] as? [String: Any])
    for requirement in security { for name in requirement.keys { #expect(schemes[name] != nil) } }
  }

  @Test func everyReferenceResolvesAndNoSchemaIsLeftUnused() async throws {
    let (_, document) = try await fetch()
    var references: [String] = []
    func collect(_ value: Any) {
      if let object = value as? [String: Any] {
        for (key, member) in object {
          if key == "$ref", let reference = member as? String { references.append(reference) } else { collect(member) }
        }
      } else if let array = value as? [Any] {
        array.forEach(collect)
      }
    }
    collect(document)
    #expect(!references.isEmpty)
    for reference in references {
      #expect(resolve(reference, in: document) != nil, "\(reference) doesn't resolve")
    }
    // Every defined schema is reachable from a path, directly or through another schema.
    let schemas = try #require((document["components"] as? [String: Any])?["schemas"] as? [String: Any])
    var reachable = Set<String>()
    func visit(_ value: Any) {
      if let object = value as? [String: Any] {
        for (key, member) in object {
          if key == "$ref", let reference = member as? String, reference.hasPrefix("#/components/schemas/") {
            let name = String(reference.dropFirst("#/components/schemas/".count))
            if reachable.insert(name).inserted, let target = schemas[name] { visit(target) }
          } else { visit(member) }
        }
      } else if let array = value as? [Any] {
        array.forEach(visit)
      }
    }
    visit(document["paths"] as Any)
    #expect(reachable == Set(schemas.keys), "unused: \(Set(schemas.keys).subtracting(reachable).sorted())")
  }

  private func resolve(_ reference: String, in document: [String: Any]) -> Any? {
    guard reference.hasPrefix("#/") else { return nil }
    var current: Any = document
    for part in reference.dropFirst(2).split(separator: "/") {
      guard let object = current as? [String: Any], let next = object[String(part)] else { return nil }
      current = next
    }
    return current
  }

  // MARK: The schemas describe what the server writes

  private func validate(_ value: Any, as name: String, in document: [String: Any], sourceLocation: SourceLocation = #_sourceLocation) {
    let problems = SchemaValidator(document: document).validate(value, against: ["$ref": "#/components/schemas/" + name], path: name)
    #expect(problems.isEmpty, "\(problems.joined(separator: "; "))", sourceLocation: sourceLocation)
  }

  private func json(_ value: some Encodable) throws -> Any {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try JSONSerialization.jsonObject(with: try encoder.encode(value))
  }

  @Test func theResponseTypesSatisfyTheirSchemas() async throws {
    let (_, document) = try await fetch()
    let device = ServiceDevice(address: address, productName: "Example", canTurnOnAndOff: true, canDim: true, value: 128, lastAnsweredAt: Date(timeIntervalSince1970: 1_800_000_000))
    let bare = ServiceDevice(address: address, productName: nil, canTurnOnAndOff: false, canDim: false, value: nil, lastAnsweredAt: nil)
    validate(try json(DeviceListDTO([device, bare], modem: .connected)), as: "DeviceList", in: document)
    validate(try json(DeviceListDTO([], modem: .unavailable(.hubErrorStatus(503)))), as: "DeviceList", in: document)

    for readiness in [ServiceHealth.Readiness.starting, .ready, .degraded] {
      for persistence in [PersistenceOutcome.notConfigured, .notAttempted, .saved, .failed] {
        let health = ServiceHealth(readiness: readiness, modem: readiness == .ready ? .connected : .unavailable(.hubUnreachable), lastHardwareExchange: Date(timeIntervalSince1970: 1_799_999_000), lastPoll: nil, deviceInformationUpdated: nil, persistence: persistence, checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        validate(try json(HealthDTO(health)), as: "Health", in: document)
      }
    }
    let noted = ServiceHealth(readiness: .ready, modem: .connected, lastHardwareExchange: nil, deviceInformationUpdated: nil, persistence: .saved, checkedAt: Date(timeIntervalSince1970: 1_800_000_000), notes: [.timeZoneUnavailable("Not/AZone"), .hubClockDrift(seconds: 90)])
    validate(try json(HealthDTO(noted)), as: "Health", in: document)

    let readings: [DeviceStatus.Reading] = [.percent(50), .onOff(true), .named("Quiet"), .raw]
    for reading in readings {
      let status = DeviceStatus(group: 1, value: 128, allLinkDatabaseDelta: 0, reading: reading, isOn: true)
      for outcome in [CommandReceipt.Outcome.read, .acknowledged] {
        for persistence in [PersistenceOutcome.notConfigured, .saved, .failed] {
          validate(try json(ReceiptDTO(CommandReceipt(address: address, outcome: outcome, status: outcome == .read ? status : nil, persistence: persistence))), as: "Receipt", in: document)
        }
      }
    }
  }

  @Test func theBackupSatisfiesItsSchemaWhateverItHolds() async throws {
    let (_, document) = try await fetch()
    let properties = (((document["components"] as? [String: Any])?["schemas"] as? [String: Any])?["HomeBackup"] as? [String: Any])?["properties"] as? [String: Any]
    #expect(properties?["schedules"] != nil)
    let rule = ServiceNotificationRule(id: "front-door", name: "Front door", trigger: .event("opened", device: address), cooldownSeconds: 30, isEnabled: true, includesDetail: false)
    let rules = [try JSONDecoder().decode(BackupValue.self, from: JSONEncoder().encode(NotificationRuleRecord(rule)))]
    let schedule = ServiceSchedule(id: "porch", name: "Porch light", when: Schedule(time: .clock(hour: 18, minute: 30), weekdays: [.monday]), action: ScheduledAction(device: address, kind: .off))
    let schedules = [try JSONDecoder().decode(BackupValue.self, from: JSONEncoder().encode(ScheduleRecord(schedule)))]
    let whole = await FakeService().homeBackup().including(notificationRules: rules, routes: [BackupRoute(kind: "relay", ticket: "ticket-1")], schedules: schedules)
    let bare = HomeBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .hubPro, modem: BackupModem(address: address, unreadable: BackupUnreadable(reason: .unavailableFromSource)), devices: [BackupDevice(address: address, name: "Lamp", type: "Example", unreadable: BackupUnreadable(reason: .damagedRecords, detail: "1 of 3 records failed their checksum"))])
    let empty = HomeBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .service, modem: nil, devices: [])
    for backup in [whole, bare, empty] {
      validate(try JSONSerialization.jsonObject(with: backup.encoded()), as: "HomeBackup", in: document)
    }
  }

  @Test func theClientTypesSatisfyTheirSchemasAndTheRequestSchemaMatchesWhatTheServerAccepts() async throws {
    let (_, document) = try await fetch()
    let record = ClientRecord(id: "0123456789abcdef", name: "Phone", scope: .control, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    let issued = IssuedClient(client: record, token: "0123456789abcdef.token")
    let pairing = PairingConfiguration(homeName: "Home", routes: [PairingRoute(kind: "lan", url: "http://insteon.local:8080"), PairingRoute(kind: "other", ticket: "t")])
    let pairingDocument = pairing.document(for: issued, serviceID: "abc")
    validate(try json(ClientListDTO(clients: [record])), as: "ClientList", in: document)
    validate(try json(ClientListDTO(clients: [])), as: "ClientList", in: document)
    validate(try json(ClientCreatedDTO(client: record, pairing: pairingDocument)), as: "ClientCreated", in: document)
    validate(try json(pairingDocument), as: "PairingDocument", in: document)
    validate(try json(PairingConfiguration().document(for: issued, serviceID: "abc")), as: "PairingDocument", in: document)
    let validator = SchemaValidator(document: document)
    let request: [String: Any] = ["$ref": "#/components/schemas/ClientRequest"]
    for scope in ClientScope.allCases {
      let body = try JSONSerialization.jsonObject(with: Data(("{\"name\":\"Phone\",\"scope\":\"" + scope.rawValue + "\"}").utf8))
      #expect(validator.validate(body, against: request, path: "ClientRequest").isEmpty)
    }
    for body in [#"{"name":"Phone"}"#, #"{"name":"Phone","scope":"root"}"#, #"{"name":"Phone","scope":"read","extra":1}"#] {
      #expect(!validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: request, path: "ClientRequest").isEmpty, "\(body)")
    }
  }

  @Test func theRouteTypesSatisfyTheirSchemasAndTheRequestSchemaMatchesWhatTheServerAccepts() async throws {
    let (_, document) = try await fetch()
    let routes = [RegisteredRoute(kind: "loopback", ticket: "127.0.0.1:9000"), RegisteredRoute(kind: "iroh", ticket: "node-ticket")]
    validate(try json(RouteListDTO(routes: routes)), as: "RouteList", in: document)
    validate(try json(RouteListDTO(routes: [])), as: "RouteList", in: document)
    for route in routes { validate(try json(RouteStoredDTO(route: route)), as: "RouteStored", in: document) }

    let validator = SchemaValidator(document: document)
    let request: [String: Any] = ["$ref": "#/components/schemas/RouteRequest"]
    for body in [#"{"ticket":"t"}"#, #"{"ticket":"127.0.0.1:9000"}"#] {
      #expect(validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: request, path: "RouteRequest").isEmpty, "\(body)")
      #expect((try? RouteRequestBody(Data(body.utf8))) != nil, "\(body)")
    }
    for body in ["{}", #"{"ticket":""}"#, #"{"ticket":7}"#, #"{"ticket":"t","extra":1}"#, #"{"ticket":"\#(String(repeating: "t", count: RouteStore.longestTicket + 1))"}"#] {
      #expect(!validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: request, path: "RouteRequest").isEmpty, "\(body.prefix(40))")
      #expect((try? RouteRequestBody(Data(body.utf8))) == nil, "\(body.prefix(40))")
    }
  }

  @Test func everyErrorBodyAndEveryEventSatisfiesItsSchema() async throws {
    let (_, document) = try await fetch()
    for code in APIErrorCode.allCases {
      validate(try json(ErrorDTO(HTTPFailure(code), requestID: "abc123")), as: "Error", in: document)
    }
    validate(try json(ErrorDTO(HTTPFailure(ServiceControlError.modemUnavailable(.credentialsRejected)), requestID: "abc123")), as: "Error", in: document)

    let receipt = CommandReceipt(address: address, outcome: .acknowledged, status: nil, persistence: .saved)
    let command = ServiceCommand(address: address, action: .on, levelPercent: 50)
    let events: [ServiceEvent] = [
      .commandCompleted(command, receipt), .identified(address, productName: "Example"), .identified(address, productName: nil),
      .setButtonPressed(address), .groupCommand(address, group: 3, name: "On"), .groupCommand(address, group: 3, name: nil),
      .heartbeat(address, group: 1), .heartbeat(address, group: nil), .statusChanged(address),
      .modemUnavailable(.hubUnreachable), .modemUnavailable(.hubErrorStatus(503)), .modemReconnected,
      .notification(ServiceNotification(ruleID: "basement-leak", ruleName: "Basement leak", device: address, firedAt: Date(timeIntervalSince1970: 1_800_000_000), eventName: nil)),
      .notification(ServiceNotification(ruleID: "basement-leak", ruleName: "Basement leak", device: address, firedAt: Date(timeIntervalSince1970: 1_800_000_000), eventName: "wet"))
    ] + [
      ScheduleRun.Outcome.acknowledged, .missed, .unavailable(.hubUnreachable), .refused(.notLinked), .unknown
    ].flatMap { outcome in
      [
        ServiceEvent.schedule(ScheduleRun(source: .schedule, id: "porch", name: "Porch light", device: address, outcome: outcome, firedAt: Date(timeIntervalSince1970: 1_800_000_000), nextRun: Date(timeIntervalSince1970: 1_800_086_400))),
        .schedule(ScheduleRun(source: .timer, id: "porch-off", name: "Porch off", device: address, outcome: outcome, firedAt: Date(timeIntervalSince1970: 1_800_000_000), nextRun: nil))
      ]
    }
    var kinds = Set<String>()
    for (index, event) in events.enumerated() {
      let frame = EventDTO(event, at: EventCursor(runID: "run1", sequence: UInt64(index + 1)))
      validate(try json(frame), as: "Event", in: document)
      validate(try json(frame), as: "StreamFrame", in: document)
      kinds.insert(frame.kind)
    }
    #expect(kinds == Set(EventKind.allCases.filter { $0 != .gap }.map(\.rawValue)), "an event kind has no sample")

    for reason in EventGapReason.allCases {
      let gap = GapDTO(reason: reason, current: EventCursor(runID: "run1", sequence: 9))
      validate(try json(gap), as: "Gap", in: document)
      validate(try json(gap), as: "StreamFrame", in: document)
    }
  }

  @Test func theNotificationRuleTypesSatisfyTheirSchemasAndTheRequestSchemaMatchesWhatTheServerAccepts() async throws {
    let (_, document) = try await fetch()
    let rules = [
      ServiceNotificationRule(id: "basement-leak", name: "Basement leak", trigger: .event("wet", device: address), cooldownSeconds: 300, isEnabled: true, includesDetail: true),
      ServiceNotificationRule(id: "paddle", name: "Paddle", trigger: .groupCommand(command1: 0x13, group: 5, device: address), cooldownSeconds: 0, isEnabled: false, includesDetail: false)
    ]
    validate(try json(NotificationRuleListDTO(rules: rules.map(NotificationRuleRecord.init))), as: "NotificationRuleList", in: document)
    validate(try json(NotificationRuleListDTO(rules: [])), as: "NotificationRuleList", in: document)
    for rule in rules { validate(try json(NotificationRuleStoredDTO(rule: NotificationRuleRecord(rule))), as: "NotificationRuleStored", in: document) }

    let validator = SchemaValidator(document: document)
    let request: [String: Any] = ["$ref": "#/components/schemas/NotificationRuleRequest"]
    let accepted = [
      NotificationRoutesTests.body,
      #"{"name":"Paddle","trigger":{"kind":"groupCommand","command1":19,"group":5,"device":"1A.2B.3C"}}"#,
      #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"enabled":false}"#
    ]
    let refused = [
      "{}", #"{"name":"Leak"}"#, #"{"trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"}}"#,
      #"{"name":"Leak","trigger":{"kind":"silence","device":"1A.2B.3C"}}"#,
      #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"extra":1}"#,
      #"{"name":"Leak","trigger":{"kind":"groupCommand","command1":300,"group":5,"device":"1A.2B.3C"}}"#,
      #"{"name":"Leak","trigger":{"kind":"event","event":"wet","device":"1A.2B.3C"},"cooldownSeconds":"5"}"#
    ]
    for body in accepted {
      #expect(validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: request, path: "NotificationRuleRequest").isEmpty, "\(body)")
      #expect((try? NotificationRuleBody(Data(body.utf8))) != nil, "\(body)")
    }
    for body in refused {
      #expect(!validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: request, path: "NotificationRuleRequest").isEmpty, "\(body)")
      #expect((try? NotificationRuleBody(Data(body.utf8))) == nil, "\(body)")
    }
  }

  @Test func theScheduleAndTimerTypesSatisfyTheirSchemasAndTheRequestSchemasMatchWhatTheServerAccepts() async throws {
    let (_, document) = try await fetch()
    let schedules = [
      ServiceSchedule(id: "porch", name: "Porch light", when: Schedule(time: .clock(hour: 18, minute: 30), weekdays: [.monday, .friday]), action: ScheduledAction(device: address, kind: .on(levelPercent: 80)), catchUp: true),
      ServiceSchedule(id: "dusk", name: "Dusk", when: Schedule(time: .sunset(offset: .seconds(-900))), action: ScheduledAction(device: address, kind: .on(levelPercent: nil))),
      ServiceSchedule(id: "dawn", name: "Dawn", isEnabled: false, when: Schedule(time: .sunrise(offset: .zero)), action: ScheduledAction(device: address, kind: .off))
    ]
    let next = Date(timeIntervalSince1970: 1_800_086_400)
    validate(try json(ScheduleListDTO(schedules: schedules.map { ScheduleRecord(ScheduleEntry(schedule: $0, nextRun: $0.isEnabled ? next : nil)) })), as: "ScheduleList", in: document)
    validate(try json(ScheduleListDTO(schedules: [])), as: "ScheduleList", in: document)
    for schedule in schedules { validate(try json(ScheduleStoredDTO(schedule: ScheduleRecord(ScheduleEntry(schedule: schedule, nextRun: next)))), as: "ScheduleStored", in: document) }
    let timer = ServiceTimer(id: "porch-off", name: "Porch off", delaySeconds: 600, action: ScheduledAction(device: address, kind: .off))
    validate(try json(TimerListDTO(timers: [TimerRecord(TimerEntry(timer: timer, dueAt: next, remainingSeconds: 600))])), as: "TimerList", in: document)
    validate(try json(TimerListDTO(timers: [])), as: "TimerList", in: document)
    validate(try json(TimerStoredDTO(timer: TimerRecord(TimerEntry(timer: timer, dueAt: next, remainingSeconds: 600)))), as: "TimerStored", in: document)

    let validator = SchemaValidator(document: document)
    let scheduleRequest: [String: Any] = ["$ref": "#/components/schemas/ScheduleRequest"]
    let accepted = [
      ScheduleRoutesTests.body,
      #"{"name":"Dusk","when":{"time":{"kind":"sunset","offsetSeconds":-900}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
      #"{"name":"Dawn","enabled":false,"when":{"time":{"kind":"sunrise"},"weekdays":["saturday"]},"action":{"device":"1A.2B.3C","action":"on"}}"#
    ]
    let refused = [
      "{}", #"{"name":"X"}"#,
      #"{"when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
      #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"},"extra":1}"#,
      #"{"name":"X","when":{"time":{"kind":"moonrise"}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
      #"{"name":"X","when":{"time":{"kind":"clock","hour":8}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
      #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0},"weekdays":["funday"]},"action":{"device":"1A.2B.3C","action":"off"}}"#,
      #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"dim"}}"#
    ]
    for body in accepted {
      #expect(validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: scheduleRequest, path: "ScheduleRequest").isEmpty, "\(body)")
      #expect((try? ScheduleBody(Data(body.utf8)).schedule(id: "x")) != nil, "\(body)")
    }
    for body in refused {
      #expect(!validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: scheduleRequest, path: "ScheduleRequest").isEmpty, "\(body)")
      #expect((try? ScheduleBody(Data(body.utf8)).schedule(id: "x")) == nil, "\(body)")
    }

    let timerRequest: [String: Any] = ["$ref": "#/components/schemas/TimerRequest"]
    #expect(validator.validate(try JSONSerialization.jsonObject(with: Data(ScheduleRoutesTests.timerBody.utf8)), against: timerRequest, path: "TimerRequest").isEmpty)
    #expect((try? TimerBody(Data(ScheduleRoutesTests.timerBody.utf8)).timer(id: "x")) != nil)
    for body in ["{}", #"{"name":"X","delaySeconds":60}"#, #"{"name":"X","delaySeconds":"60","action":{"device":"1A.2B.3C","action":"off"}}"#, #"{"name":"X","delaySeconds":60,"action":{"device":"1A.2B.3C","action":"off"},"extra":1}"#] {
      #expect(!validator.validate(try JSONSerialization.jsonObject(with: Data(body.utf8)), against: timerRequest, path: "TimerRequest").isEmpty, "\(body)")
      #expect((try? TimerBody(Data(body.utf8)).timer(id: "x")) == nil, "\(body)")
    }
  }

  @Test func theCommandSchemaAcceptsWhatTheServerAcceptsAndRefusesWhatItRefuses() async throws {
    let (_, document) = try await fetch()
    let validator = SchemaValidator(document: document)
    let command: [String: Any] = ["$ref": "#/components/schemas/Command"]
    for body in [#"{"action":"on"}"#, #"{"action":"on","levelPercent":50}"#, #"{"action":"status"}"#, #"{"levelPercent":0,"action":"off"}"#] {
      let value = try JSONSerialization.jsonObject(with: Data(body.utf8))
      #expect(validator.validate(value, against: command, path: "Command").isEmpty, "\(body)")
      #expect(try JSONDecoder().decode(HTTPCommand.self, from: Data(body.utf8)).action.rawValue.isEmpty == false)
    }
    for body in [#"{}"#, #"{"action":"remove"}"#, #"{"action":"on","levelPercent":101}"#, #"{"action":"on","levle":50}"#, #"{"action":"on","levelPercent":"50"}"#] {
      let value = try JSONSerialization.jsonObject(with: Data(body.utf8))
      #expect(!validator.validate(value, against: command, path: "Command").isEmpty, "\(body)")
    }
  }

  @Test func theIdempotencyKeyPatternMatchesTheKeysTheServerAccepts() async throws {
    let (_, document) = try await fetch()
    let route = try #require(described(document).first { $0.operation["operationId"] as? String == "executeCommand" })
    let parameters = try #require(route.operation["parameters"] as? [[String: Any]])
    let key = try #require(parameters.first { $0["name"] as? String == "Idempotency-Key" })
    let pattern = try #require((key["schema"] as? [String: Any])?["pattern"] as? String)
    let expression = try NSRegularExpression(pattern: pattern)
    for sample in ["a", "A-z_0.9~:", String(repeating: "k", count: 128), "", "has space", "semi;colon", String(repeating: "k", count: 129), "caf\u{E9}"] {
      let matches = expression.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)) != nil
      let accepted = (try? IdempotencyKey(header: [sample])) != nil
      #expect(matches == accepted, "\(sample)")
    }
  }

  // MARK: Served bytes

  @Test func theServedBytesAreTheSameEveryTime() async throws {
    let first = try await fetch().bytes
    let second = try await fetch().bytes
    #expect(!first.isEmpty)
    #expect(first == second)
    #expect(first == OpenAPIDocument.bytes)
    #expect(try OpenAPIDocument.document.encoded() == OpenAPIDocument.document.encoded())
  }

  @Test func theDocumentNeedsTheGatewayPassword() async throws {
    let app = try application()
    try await app.test(.router) { client in
      for headers: HTTPFields in [[:], [.authorization: "Basic incorrect"]] {
        let response = try await client.execute(uri: "/api/v1/openapi.json", method: .get, headers: headers)
        #expect(response.status == .unauthorized)
        #expect(response.headers[.wwwAuthenticate] != nil)
        let body = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        #expect(["authenticationRequired", "authenticationFailed"].contains(body["code"] as? String ?? ""))
      }
    }
  }
}

/// Enough of JSON Schema to check the descriptions: type, enum, const, required, properties,
/// additionalProperties, items, oneOf, minimum, maximum and references inside the document.
struct SchemaValidator {
  let document: [String: Any]

  func validate(_ value: Any, against schema: [String: Any], path: String) -> [String] {
    if let reference = schema["$ref"] as? String {
      var target: Any = document
      for part in reference.dropFirst(2).split(separator: "/") { target = (target as? [String: Any])?[String(part)] as Any }
      guard let resolved = target as? [String: Any] else { return ["\(path): \(reference) doesn't resolve"] }
      return validate(value, against: resolved, path: path)
    }
    if let options = schema["oneOf"] as? [[String: Any]] {
      let matching = options.filter { validate(value, against: $0, path: path).isEmpty }.count
      return matching == 1 ? [] : ["\(path): matches \(matching) of \(options.count) alternatives"]
    }
    var problems: [String] = []
    if let constant = schema["const"], !equal(value, constant) { problems.append("\(path): not the constant \(constant)") }
    if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { equal(value, $0) }) { problems.append("\(path): \(value) isn't one of \(allowed)") }
    if let type = schema["type"] as? String, !matches(value, type: type) { return problems + ["\(path): \(value) isn't \(type)"] }
    if let number = value as? NSNumber, !(value is Bool), String(cString: number.objCType) != "c" {
      if let minimum = schema["minimum"] as? Int, number.intValue < minimum { problems.append("\(path): below \(minimum)") }
      if let maximum = schema["maximum"] as? Int, number.intValue > maximum { problems.append("\(path): above \(maximum)") }
    }
    if let text = value as? String, let pattern = schema["pattern"] as? String, let expression = try? NSRegularExpression(pattern: pattern),
       expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil {
      problems.append("\(path): doesn't match \(pattern)")
    }
    if let object = value as? [String: Any], schema["type"] as? String == "object" {
      let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
      for name in schema["required"] as? [String] ?? [] where object[name] == nil { problems.append("\(path): missing \(name)") }
      for (name, member) in object {
        if let property = properties[name] { problems += validate(member, against: property, path: path + "." + name) }
        else if schema["additionalProperties"] as? Bool == false { problems.append("\(path): unexpected \(name)") }
      }
    }
    if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
      for (index, element) in array.enumerated() { problems += validate(element, against: items, path: "\(path)[\(index)]") }
    }
    return problems
  }

  private func matches(_ value: Any, type: String) -> Bool {
    switch type {
    case "string": value is String
    case "boolean": (value as? NSNumber).map { String(cString: $0.objCType) == "c" } ?? false
    case "integer": (value as? NSNumber).map { String(cString: $0.objCType) != "c" && $0.doubleValue == Double($0.intValue) } ?? false
    case "object": value is [String: Any]
    case "array": value is [Any]
    case "null": value is NSNull
    default: false
    }
  }

  private func equal(_ left: Any, _ right: Any) -> Bool {
    if let left = left as? String, let right = right as? String { return left == right }
    if let left = left as? NSNumber, let right = right as? NSNumber { return left == right }
    return false
  }
}
