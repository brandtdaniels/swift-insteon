import Foundation
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonService
import Testing
@testable import InsteonServerSupport

/// A keyed command through the real server, router and service over the scripted modem
/// connection: it runs once, and a repeat gets the recorded answer.
@Suite(.timeLimit(.minutes(1)))
struct IdempotencyServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  private func send(_ server: RunningServer, _ body: String = #"{"action":"on"}"#, key: String? = "key-0001", path: String = "/api/v1/devices/1A.2B.3C/commands") async throws -> (status: Int, json: [String: Any], headers: [String: String]) {
    try await server.exchange(path, method: "POST", body: body, headers: key.map { ["Idempotency-Key": $0] } ?? [:], password: gatewayPassword)
  }

  private func connected(now: @escaping @Sendable () -> Date = { Date() }) async throws -> (server: RunningServer, link: HubLink) {
    let link = HubLink()
    let server = try await start(try scratch(), now: now, openModem: opener(ScriptedHubOpener([.connect(link)])))
    _ = await server.code("modem_connected")
    return (server, link)
  }

  @Test func aRepeatedKeyedCommandReturnsTheRecordedResponseAndSendsNothing() async throws {
    let (server, link) = try await connected()
    let first = try await send(server)
    let second = try await send(server)
    #expect(first.status == 200)
    #expect(first.headers["idempotent-replay"] == nil)
    #expect(second.status == 200)
    #expect(second.headers["idempotent-replay"] == "true")
    #expect(NSDictionary(dictionary: second.json).isEqual(to: first.json))
    #expect(await link.modem.requestCounts[device] == 1)
    await server.stop()
  }

  @Test func aCommandWithoutAKeyIsSentEveryTime() async throws {
    let (server, link) = try await connected()
    _ = try await send(server, key: nil)
    let again = try await send(server, key: nil)
    #expect(again.headers["idempotent-replay"] == nil)
    #expect(await link.modem.requestCounts[device] == 2)
    await server.stop()
  }

  @Test func theSameBodyInADifferentOrderIsTheSameCommand() async throws {
    let (server, link) = try await connected()
    _ = try await send(server, #"{"action":"on","levelPercent":50}"#)
    let again = try await send(server, #"{ "levelPercent": 50, "action": "on" }"#)
    #expect(again.headers["idempotent-replay"] == "true")
    #expect(await link.modem.requestCounts[device] == 1)
    await server.stop()
  }

  // MARK: Outcomes that are recorded

  @Test func anOutcomeUnknownIsReplayedAndTheControlIsNotSentAgain() async throws {
    let (server, link) = try await connected()
    await link.modem.fail(device, with: ModemError.deviceTimedOut(device))
    let first = try await send(server)
    let second = try await send(server)
    for result in [first, second] {
      #expect(result.status == 502)
      #expect(result.json["code"] as? String == "outcomeUnknown")
      #expect(result.json["sent"] as? Bool == true)
    }
    #expect(first.headers["idempotent-replay"] == nil)
    #expect(second.headers["idempotent-replay"] == "true")
    // The replay reports the repeated request's own id, so it finds its own log record.
    #expect(second.json["requestId"] as? String != first.json["requestId"] as? String)
    #expect(await link.modem.requestCounts[device] == 1)
    await server.stop()
  }

  // MARK: Outcomes that are not recorded

  @Test func aBusyRefusalIsNotRecordedSoTheSameKeyWorksOnceTheGateIsFree() async throws {
    let (server, link) = try await connected()
    let arrivals = await link.modem.hold()
    let password = gatewayPassword
    let first = Task { try await server.exchange("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, headers: ["Idempotency-Key": "key-first"], password: password).status }
    var waiting = arrivals.makeAsyncIterator()
    _ = await waiting.next()
    let busy = try await send(server, #"{"action":"off"}"#, key: "key-second")
    #expect(busy.status == 409)
    #expect(busy.json["code"] as? String == "busy")
    await link.modem.release()
    #expect(try await first.value == 200)
    let retried = try await send(server, #"{"action":"off"}"#, key: "key-second")
    #expect(retried.status == 200)
    #expect(retried.headers["idempotent-replay"] == nil)
    #expect(await link.modem.levels[device] == 0)
    await server.stop()
  }

  @Test func aRefusalBeforeSendingIsNotRecordedSoTheKeyWorksOnceTheModemIsBack() async throws {
    let first = HubLink()
    let second = HubLink()
    let away = HubStoppedAnswering(underlyingError: URLError(.timedOut))
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(away), .connect(first), .connect(second)])))
    _ = await server.code("hub_unreachable")
    #expect(try await send(server).status == 503)
    server.retries.release()
    _ = await server.code("modem_connected")
    let retried = try await send(server)
    #expect(retried.status == 200)
    #expect(retried.headers["idempotent-replay"] == nil)
    #expect(await first.modem.requestCounts[device] == 1)
    await server.stop()
  }

  // MARK: Reuse and malformed keys

  @Test func theSameKeyWithADifferentBodyOrDeviceIsRefusedAndNothingIsSent() async throws {
    let (server, link) = try await connected()
    _ = try await send(server)
    let otherBody = try await send(server, #"{"action":"off"}"#)
    #expect(otherBody.status == 422)
    #expect(otherBody.json["code"] as? String == "idempotencyKeyReused")
    #expect(otherBody.json["sent"] as? Bool == false)
    let otherPath = try await send(server, path: "/api/v1/devices/AA.BB.CC/commands")
    #expect(otherPath.status == 422)
    #expect(otherPath.json["code"] as? String == "idempotencyKeyReused")
    #expect(await link.modem.requestCounts[device] == 1)
    await server.stop()
  }

  @Test(arguments: ["", "has space", "semi;colon", "caf\u{E9}", String(repeating: "k", count: 129)])
  func aMalformedKeyIsRefusedBeforeAnythingIsSent(_ key: String) async throws {
    let (server, link) = try await connected()
    let result = try await send(server, key: key)
    #expect(result.status == 400)
    #expect(result.json["code"] as? String == "invalidIdempotencyKey")
    #expect(result.json["sent"] as? Bool == false)
    #expect(await link.modem.requestCounts[device] == nil)
    await server.stop()
  }

  // MARK: Bounded memory

  @Test func aRecordedAnswerExpiresAfterTheRetentionPeriod() async throws {
    let manual = ManualNow(Date(timeIntervalSince1970: 1_800_000_000))
    let (server, link) = try await connected(now: { manual.now })
    _ = try await send(server)
    manual.advance(by: 599)
    #expect(try await send(server).headers["idempotent-replay"] == "true")
    manual.advance(by: 2)
    let expired = try await send(server)
    #expect(expired.headers["idempotent-replay"] == nil)
    #expect(await link.modem.requestCounts[device] == 2)
    await server.stop()
  }
}
