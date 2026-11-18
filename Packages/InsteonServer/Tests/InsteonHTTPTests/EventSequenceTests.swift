import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonService
import Testing
@testable import InsteonHTTP

/// How the event stream numbers its frames and reads the id a reconnecting client sends back.
@Suite(.timeLimit(.minutes(1)))
struct EventSequenceTests {
  let password = String(repeating: "p", count: 40)
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  private var authorization: HTTPFields { [.authorization: "Basic " + Data(("insteon:" + password).utf8).base64EncodedString()] }

  private func frames(_ service: FakeService, uri: String = "/api/v1/events", headers: HTTPFields = [:]) async throws -> [String] {
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    var merged = authorization
    for field in headers { merged.append(field) }
    let fields = merged
    return try await app.test(.router) { client in
      let response = try await client.execute(uri: uri, method: .get, headers: fields)
      return String(buffer: response.body).components(separatedBy: "\n\n").filter { !$0.isEmpty && !$0.hasPrefix(":") }
    }
  }

  private func json(_ frame: String) throws -> [String: Any] {
    let line = try #require(frame.split(separator: "\n").first { $0.hasPrefix("data: ") })
    return try #require(try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any])
  }

  @Test func eachFrameCarriesItsIdAndTheRunAndNumberInItsData() async throws {
    let (source, events) = AsyncStream<ServiceEvent>.makeStream()
    events.yield(.statusChanged(address))
    events.yield(.identified(address, productName: nil))
    events.finish()
    let result = try await frames(FakeService(eventStream: source))
    #expect(result.count == 2)
    #expect(result[0].hasPrefix("id: fake-1\ndata: "))
    #expect(result[1].hasPrefix("id: fake-2\ndata: "))
    let first = try json(result[0])
    #expect(first["runId"] as? String == "fake")
    #expect(first["sequence"] as? Int == 1)
    #expect(first["kind"] as? String == "statusChanged")
    #expect(first["version"] as? Int == 1)
  }

  @Test func aGapIsOneFrameWithTheReasonAndTheCurrentRunAndNumber() async throws {
    let current = EventCursor(runID: "fake", sequence: 9)
    let service = FakeService(scriptedItems: [.gap(.tooOld, current: current)])
    let result = try await frames(service)
    let gap = try #require(result.first)
    #expect(gap.hasPrefix("id: fake-9\ndata: "))
    let body = try json(gap)
    #expect(body["kind"] as? String == "gap")
    #expect(body["reason"] as? String == "tooOld")
    #expect(body["runId"] as? String == "fake")
    #expect(body["sequence"] as? Int == 9)
    #expect(body["version"] as? Int == 1)
  }

  @Test func aFreshStreamStartsWithTheRunsPositionAsABareIdSoABrowserCanResumeInAQuietHouse() async throws {
    let service = FakeService(scriptedItems: [.position(EventCursor(runID: "fake", sequence: 4))])
    let result = try await frames(service)
    #expect(result.first == "id: fake-4")
  }

  @Test(arguments: [EventGapReason.otherRun, .tooOld, .ahead])
  func everyGapReasonHasItsOwnName(_ reason: EventGapReason) async throws {
    let service = FakeService(scriptedItems: [.gap(reason, current: EventCursor(runID: "fake", sequence: 1))])
    let body = try json(try #require(try await frames(service).first))
    #expect(body["reason"] as? String == reason.rawValue)
  }

  // MARK: What the client sends back

  @Test func theLastEventIDHeaderIsTheCursorTheServiceResumesFrom() async throws {
    let service = FakeService()
    _ = try await frames(service, headers: [HTTPField.Name("Last-Event-ID")!: "abc123-5"])
    #expect(await service.cursors == [EventCursor(runID: "abc123", sequence: 5)])
  }

  @Test func theQueryParameterServesAClientThatCannotSetTheHeader() async throws {
    let service = FakeService()
    _ = try await frames(service, uri: "/api/v1/events?lastEventId=abc123-7")
    #expect(await service.cursors == [EventCursor(runID: "abc123", sequence: 7)])
  }

  @Test func theHeaderWinsOverTheQueryParameter() async throws {
    let service = FakeService()
    _ = try await frames(service, uri: "/api/v1/events?lastEventId=abc123-7", headers: [HTTPField.Name("Last-Event-ID")!: "abc123-5"])
    #expect(await service.cursors == [EventCursor(runID: "abc123", sequence: 5)])
  }

  @Test func noIdMeansAFreshSubscription() async throws {
    let service = FakeService()
    _ = try await frames(service)
    #expect(await service.cursors == [nil])
  }

  @Test(arguments: ["garbage", "5", "-5", "run-x", "a-b-1", String(repeating: "x", count: 300)])
  func anIdTheServerCannotReadIsTreatedAsAnotherRun(_ id: String) async throws {
    let service = FakeService()
    _ = try await frames(service, headers: [HTTPField.Name("Last-Event-ID")!: id])
    #expect(await service.cursors == [EventCursor.unrecognized])
  }
}
