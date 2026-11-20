import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonProtocol
import InsteonScheduling
import InsteonService
import Testing
@testable import InsteonHTTP

/// Managing schedules and timers through the real router. Reading needs the `read` scope; writing needs `admin`.
@Suite(.timeLimit(.minutes(1)))
struct ScheduleRoutesTests {
  let password = String(repeating: "p", count: 40)
  private var basic: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }
  static let body = #"{"name":"Porch light","when":{"time":{"kind":"clock","hour":18,"minute":30},"weekdays":["monday","friday"]},"action":{"device":"1A.2B.3C","action":"on","levelPercent":80},"catchUp":true}"#
  static let timerBody = #"{"name":"Porch off","delaySeconds":600,"action":{"device":"1A.2B.3C","action":"off"}}"#
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)

  private struct Setup {
    let service: FakeService
    let clients: ClientStore
    let app: Application<RouterResponder<BasicRequestContext>>
    init(password: String, service: FakeService = FakeService()) throws {
      let clients = ClientStore(persistence: InMemoryClientPersistence())
      self.service = service
      self.clients = clients
      app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), clients: clients).buildResponder())
    }
  }

  private func headers(_ authorization: String, json: Bool = true, marker: Bool = true) -> HTTPFields {
    var fields: HTTPFields = [.authorization: authorization]
    if marker { fields[HTTPField.Name("X-Insteon-Request")!] = "1" }
    if json { fields[.contentType] = "application/json" }
    return fields
  }

  private func object(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  private func putSchedule(_ client: some TestClientProtocol, _ id: String = "porch", body: String = ScheduleRoutesTests.body, as authorization: String) async throws -> TestResponse {
    try await client.execute(uri: "/api/v1/schedules/" + id, method: .put, headers: headers(authorization), body: ByteBuffer(string: body))
  }

  private func putTimer(_ client: some TestClientProtocol, _ id: String = "porch-off", body: String = ScheduleRoutesTests.timerBody, as authorization: String) async throws -> TestResponse {
    try await client.execute(uri: "/api/v1/timers/" + id, method: .put, headers: headers(authorization), body: ByteBuffer(string: body))
  }

  private func token(_ setup: Setup, scope: ClientScope) async throws -> String {
    "Bearer " + (try await setup.clients.issue(name: "Client", scope: scope)).token
  }

  // MARK: Schedules

  @Test func anAdminStoresAScheduleAndAnyReaderListsItWithItsNextRun() async throws {
    let setup = try Setup(password: password)
    let reader = try await token(setup, scope: .read)
    try await setup.app.test(.router) { client in
      let empty = try await client.execute(uri: "/api/v1/schedules", method: .get, headers: [.authorization: reader])
      #expect(empty.status == .ok)
      #expect((try object(empty)["schedules"] as? [Any])?.isEmpty == true)

      let stored = try await putSchedule(client, as: basic)
      #expect(stored.status == .ok)
      let schedule = try #require(try object(stored)["schedule"] as? [String: Any])
      #expect(schedule["id"] as? String == "porch" && schedule["name"] as? String == "Porch light")
      #expect(schedule["enabled"] as? Bool == true && schedule["catchUp"] as? Bool == true)
      #expect(schedule["nextRun"] as? String == "2027-01-15T09:00:00Z")
      let when = try #require(schedule["when"] as? [String: Any])
      #expect(when["weekdays"] as? [String] == ["monday", "friday"])
      let time = try #require(when["time"] as? [String: Any])
      #expect(time["kind"] as? String == "clock" && time["hour"] as? Int == 18 && time["minute"] as? Int == 30)
      let action = try #require(schedule["action"] as? [String: Any])
      #expect(action["device"] as? String == "1A.2B.3C" && action["action"] as? String == "on" && action["levelPercent"] as? Int == 80)

      let listed = try await client.execute(uri: "/api/v1/schedules", method: .get, headers: [.authorization: reader])
      #expect((try object(listed)["schedules"] as? [[String: Any]])?.count == 1)
    }
    let schedules = await setup.service.storedSchedules
    #expect(schedules == [ServiceSchedule(id: "porch", name: "Porch light", when: Schedule(time: .clock(hour: 18, minute: 30), weekdays: [.monday, .friday]), action: ScheduledAction(device: address, kind: .on(levelPercent: 80)), catchUp: true)])
  }

  @Test func aSunsetScheduleKeepsItsOffsetAndTheDefaultsApply() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let stored = try await putSchedule(client, body: #"{"name":"Dusk","when":{"time":{"kind":"sunset","offsetSeconds":-900}},"action":{"device":"1A.2B.3C","action":"off"}}"#, as: basic)
      #expect(stored.status == .ok)
      let schedule = try #require(try object(stored)["schedule"] as? [String: Any])
      #expect(schedule["enabled"] as? Bool == true && schedule["catchUp"] as? Bool == false)
      let when = try #require(schedule["when"] as? [String: Any])
      #expect((when["weekdays"] as? [String])?.count == 7)
      #expect((when["time"] as? [String: Any])?["offsetSeconds"] as? Int == -900)
    }
    #expect(await setup.service.storedSchedules.first?.when.time == .sunset(offset: .seconds(-900)))
  }

  @Test func aDisabledScheduleHasNoNextRun() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let stored = try await putSchedule(client, body: #"{"name":"Off","enabled":false,"when":{"time":{"kind":"clock","hour":1,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#, as: basic)
      let schedule = try #require(try object(stored)["schedule"] as? [String: Any])
      #expect(schedule["enabled"] as? Bool == false)
      #expect(schedule["nextRun"] is NSNull)
    }
  }

  @Test func anAdminRemovesAScheduleAndAnUnknownOneIsReported() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      _ = try await putSchedule(client, as: basic)
      let removed = try await client.execute(uri: "/api/v1/schedules/porch", method: .delete, headers: headers(basic, json: false))
      #expect(removed.status == .noContent)
      let again = try await client.execute(uri: "/api/v1/schedules/porch", method: .delete, headers: headers(basic, json: false))
      #expect(again.status == .notFound)
      #expect(try object(again)["code"] as? String == "unknownSchedule")
    }
    #expect(await setup.service.storedSchedules.isEmpty)
  }

  // MARK: Timers

  @Test func anAdminStartsATimerAndAnyReaderListsItAndAdminCancelsIt() async throws {
    let setup = try Setup(password: password)
    let reader = try await token(setup, scope: .read)
    try await setup.app.test(.router) { client in
      let started = try await putTimer(client, as: basic)
      #expect(started.status == .ok)
      let timer = try #require(try object(started)["timer"] as? [String: Any])
      #expect(timer["id"] as? String == "porch-off" && timer["delaySeconds"] as? Int == 600 && timer["remainingSeconds"] as? Int == 600)
      #expect(timer["dueAt"] as? String == "2027-01-15T09:00:00Z")
      #expect((timer["action"] as? [String: Any])?["action"] as? String == "off")

      let listed = try await client.execute(uri: "/api/v1/timers", method: .get, headers: [.authorization: reader])
      #expect((try object(listed)["timers"] as? [[String: Any]])?.count == 1)

      let canceled = try await client.execute(uri: "/api/v1/timers/porch-off", method: .delete, headers: headers(basic, json: false))
      #expect(canceled.status == .noContent)
      let again = try await client.execute(uri: "/api/v1/timers/porch-off", method: .delete, headers: headers(basic, json: false))
      #expect(try object(again)["code"] as? String == "unknownTimer")
    }
    #expect(await setup.service.storedTimers.isEmpty)
  }

  // MARK: Scope

  @Test func onlyAnAdminChangesSchedulesAndTimers() async throws {
    let setup = try Setup(password: password)
    let reader = try await token(setup, scope: .read)
    let controller = try await token(setup, scope: .control)
    try await setup.app.test(.router) { client in
      _ = try await putSchedule(client, as: basic)
      _ = try await putTimer(client, as: basic)
      for authorization in [reader, controller] {
        for response in [
          try await putSchedule(client, body: #"{"name":"Changed","when":{"time":{"kind":"clock","hour":1,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#, as: authorization),
          try await putTimer(client, as: authorization),
          try await client.execute(uri: "/api/v1/schedules/porch", method: .delete, headers: headers(authorization, json: false)),
          try await client.execute(uri: "/api/v1/timers/porch-off", method: .delete, headers: headers(authorization, json: false))
        ] {
          #expect(response.status == .forbidden)
          #expect(try object(response)["code"] as? String == "forbidden")
        }
      }
      for path in ["/api/v1/schedules", "/api/v1/timers"] {
        let listed = try await client.execute(uri: path, method: .get, headers: [.authorization: controller])
        #expect(listed.status == .ok)
        let anonymous = try await client.execute(uri: path, method: .get, headers: [:])
        #expect(anonymous.status == .unauthorized)
      }
    }
    #expect(await setup.service.storedSchedules.map(\.name) == ["Porch light"])
    #expect(await setup.service.storedTimers.count == 1)
  }

  @Test func aWriteWithoutTheMarkerOrTheRightMediaTypeIsRefused() async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let unmarked = try await client.execute(uri: "/api/v1/schedules/porch", method: .put, headers: headers(basic, marker: false), body: ByteBuffer(string: Self.body))
      #expect(unmarked.status == .forbidden)
      #expect(try object(unmarked)["code"] as? String == "apiMarkerMissing")
      let plain = try await client.execute(uri: "/api/v1/timers/t", method: .put, headers: [.authorization: basic, .contentType: "text/plain", HTTPField.Name("X-Insteon-Request")!: "1"], body: ByteBuffer(string: Self.timerBody))
      #expect(plain.status == .unsupportedMediaType)
    }
    let schedules = await setup.service.storedSchedules
    let timers = await setup.service.storedTimers
    #expect(schedules.isEmpty && timers.isEmpty)
  }

  // MARK: Input

  @Test(arguments: [
    "not json", "[]", "{}",
    #"{"when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0}}}"#,
    #"{"name":7,"when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"},"extra":1}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0},"extra":1},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0,"offsetSeconds":5}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"sunset","hour":8}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"moonrise"}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":"8","minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0},"weekdays":["funday"]},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0},"weekdays":["monday","monday"]},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0},"weekdays":"monday"},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"nope","action":"off"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"dim"}}"#,
    #"{"name":"X","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off","levelPercent":50}}"#,
    #"{"name":"X","enabled":"yes","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","catchUp":1,"when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#
  ])
  func aScheduleBodyThatIsntOneIsRefusedAndStoresNothing(_ body: String) async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await putSchedule(client, body: body, as: basic)
      #expect(response.status == .badRequest)
      #expect(try object(response)["code"] as? String == "invalidSchedule")
    }
    #expect(await setup.service.storedSchedules.isEmpty)
  }

  @Test(arguments: [
    "not json", "{}",
    #"{"name":"X","delaySeconds":"60","action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","delaySeconds":60.5,"action":{"device":"1A.2B.3C","action":"off"}}"#,
    #"{"name":"X","delaySeconds":60}"#,
    #"{"name":"X","delaySeconds":60,"action":{"device":"1A.2B.3C","action":"nope"}}"#,
    #"{"name":"X","delaySeconds":60,"action":{"device":"1A.2B.3C","action":"off"},"extra":true}"#
  ])
  func aTimerBodyThatIsntOneIsRefusedAndStartsNothing(_ body: String) async throws {
    let setup = try Setup(password: password)
    try await setup.app.test(.router) { client in
      let response = try await putTimer(client, body: body, as: basic)
      #expect(response.status == .badRequest)
      #expect(try object(response)["code"] as? String == "invalidTimer")
    }
    #expect(await setup.service.storedTimers.isEmpty)
  }

  // MARK: What the service refuses

  @Test(arguments: [
    (ScheduleError.invalidSchedule, HTTPResponse.Status.badRequest, "invalidSchedule"),
    (.unknownDevice, .notFound, "unknownDevice"),
    (.unsupportedAction, .unprocessableContent, "unsupportedControl"),
    (.locationMissing, .conflict, "locationNotConfigured"),
    (.timeZoneUnavailable, .conflict, "timeZoneUnavailable"),
    (.scheduleLimitReached, .conflict, "scheduleLimitReached"),
    (.notSaved, .internalServerError, "schedulesNotSaved")
  ])
  func aRefusedScheduleAnswersWithATypedError(_ error: ScheduleError, _ status: HTTPResponse.Status, _ code: String) async throws {
    let setup = try Setup(password: password, service: FakeService())
    await setup.service.failSchedules(with: error)
    try await setup.app.test(.router) { client in
      let response = try await putSchedule(client, as: basic)
      #expect(response.status == status)
      #expect(try object(response)["code"] as? String == code)
      #expect(try object(response)["sent"] as? Bool == false)
    }
  }

  @Test(arguments: [
    (ScheduleError.invalidTimer, HTTPResponse.Status.badRequest, "invalidTimer"),
    (.timerLimitReached, .conflict, "timerLimitReached"),
    (.notSaved, .internalServerError, "schedulesNotSaved")
  ])
  func aRefusedTimerAnswersWithATypedError(_ error: ScheduleError, _ status: HTTPResponse.Status, _ code: String) async throws {
    let setup = try Setup(password: password, service: FakeService())
    await setup.service.failSchedules(with: error)
    try await setup.app.test(.router) { client in
      let response = try await putTimer(client, as: basic)
      #expect(response.status == status)
      #expect(try object(response)["code"] as? String == code)
    }
  }

  @Test func listingWhenTheStoredSchedulesCantBeReadSaysSo() async throws {
    let setup = try Setup(password: password)
    await setup.service.failSchedules(with: .notSaved)
    try await setup.app.test(.router) { client in
      for path in ["/api/v1/schedules", "/api/v1/timers"] {
        let response = try await client.execute(uri: path, method: .get, headers: [.authorization: basic])
        #expect(response.status == .internalServerError)
        #expect(try object(response)["code"] as? String == "schedulesNotSaved")
      }
    }
  }

  // MARK: Health

  @Test func healthCarriesNotesAndAnEmptyListWithoutAny() async throws {
    let service = FakeService()
    let setup = try Setup(password: password, service: service)
    try await setup.app.test(.router) { client in
      let quiet = try await client.execute(uri: "/api/v1/health", method: .get, headers: [.authorization: basic])
      #expect((try object(quiet)["notes"] as? [Any])?.isEmpty == true)

      await service.setHealth(ServiceHealth(readiness: .ready, modem: .connected, lastHardwareExchange: nil, deviceInformationUpdated: nil, persistence: .saved, checkedAt: Date(timeIntervalSince1970: 1_800_000_000), notes: [.timeZoneUnavailable("Not/AZone"), .hubClockDrift(seconds: -120)]))
      let noted = try await client.execute(uri: "/api/v1/health", method: .get, headers: [.authorization: basic])
      let notes = try #require(try object(noted)["notes"] as? [[String: String]])
      #expect(notes.map { $0["code"] } == ["timeZoneUnavailable", "hubClockDrift"])
      #expect(!(notes.compactMap { $0["message"] }.joined().contains("Not/AZone")))
    }
  }

  // MARK: Events

  @Test func aScheduleRunIsAFrameOnTheStreamWithItsOutcomeAndNextRun() throws {
    let run = ScheduleRun(source: .schedule, id: "porch", name: "Porch light", device: address, outcome: .refused(.notLinked), firedAt: Date(timeIntervalSince1970: 1_800_000_000), nextRun: Date(timeIntervalSince1970: 1_800_086_400))
    let frame = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EventDTO(.schedule(run), at: EventCursor(runID: "run1", sequence: 7)))) as? [String: Any]
    #expect(frame?["kind"] as? String == "schedule")
    #expect(frame?["scheduleId"] as? String == "porch" && frame?["name"] as? String == "Porch light" && frame?["address"] as? String == "1A.2B.3C")
    #expect(frame?["source"] as? String == "schedule" && frame?["outcome"] as? String == "refused" && frame?["reason"] as? String == "notLinked")
    #expect(frame?["firedAt"] as? String == "2027-01-15T08:00:00Z" && frame?["nextRun"] as? String == "2027-01-16T08:00:00Z")
  }

  @Test func anUnavailableRunNamesTheCauseAndATimerHasNoNextRun() throws {
    let run = ScheduleRun(source: .timer, id: "t", name: "Timer", device: address, outcome: .unavailable(.hubUnreachable), firedAt: Date(timeIntervalSince1970: 1_800_000_000), nextRun: nil)
    let frame = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EventDTO(.schedule(run), at: EventCursor(runID: "run1", sequence: 8)))) as? [String: Any]
    #expect(frame?["source"] as? String == "timer" && frame?["outcome"] as? String == "unavailable" && frame?["cause"] as? String == "hubUnreachable")
    #expect(frame?["nextRun"] == nil)
  }
}
