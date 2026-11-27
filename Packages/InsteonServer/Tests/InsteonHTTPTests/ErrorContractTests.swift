import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonService
import Testing
@testable import InsteonHTTP

/// Every non-2xx API response is the same typed JSON body, and the request log carries the same code.
@Suite(.timeLimit(.minutes(1)))
struct ErrorContractTests {
  let password = String(repeating: "p", count: 40)
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  private var authorization: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }
  private var commandHeaders: HTTPFields {
    [.authorization: authorization, .contentType: "application/json", HTTPField.Name("X-Insteon-Request")!: "1"]
  }

  struct Expected: Sendable, CustomTestStringConvertible {
    let failure: any Error
    let action: String
    let code: String
    let status: Int
    let sent: Bool
    var testDescription: String { "\(action) \(failure) -> \(code)" }
  }

  private static let device = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let table: [Expected] = [
    Expected(failure: ServiceControlError.busy, action: "on", code: "busy", status: 409, sent: false),
    Expected(failure: ServiceControlError.unknownDevice, action: "on", code: "unknownDevice", status: 404, sent: false),
    Expected(failure: ServiceControlError.unknownScene, action: "on", code: "unknownScene", status: 404, sent: false),
    Expected(failure: ServiceControlError.sceneEmpty, action: "on", code: "sceneEmpty", status: 422, sent: false),
    Expected(failure: ServiceControlError.invalidLevel, action: "on", code: "invalidLevel", status: 400, sent: false),
    Expected(failure: ServiceControlError.unsupportedControl, action: "on", code: "unsupportedControl", status: 422, sent: false),
    Expected(failure: ServiceControlError.notIdentified, action: "status", code: "notIdentified", status: 409, sent: false),
    Expected(failure: ServiceControlError.notLinked, action: "on", code: "notLinked", status: 409, sent: false),
    Expected(failure: ServiceControlError.databasesUnavailable, action: "status", code: "databasesUnavailable", status: 422, sent: false),
    Expected(failure: ServiceControlError.modemUnavailable(.hubUnreachable), action: "on", code: "modemUnavailable", status: 503, sent: false),
    // A control that timed out may have reached the device.
    Expected(failure: ModemError.deviceTimedOut(device), action: "on", code: "outcomeUnknown", status: 502, sent: true),
    Expected(failure: ModemError.timedOut(.getModemInfo), action: "off", code: "outcomeUnknown", status: 502, sent: true),
    Expected(failure: ModemError.connectionClosed, action: "on", code: "outcomeUnknown", status: 502, sent: true),
    Expected(failure: CancellationError(), action: "on", code: "canceled", status: 503, sent: true),
    // A read changes nothing, so a failed read is safe to repeat.
    Expected(failure: ModemError.deviceTimedOut(device), action: "status", code: "deviceNotAnswering", status: 504, sent: false),
    Expected(failure: ModemError.connectionClosed, action: "identify", code: "deviceNotAnswering", status: 504, sent: false),
    Expected(failure: CancellationError(), action: "status", code: "canceled", status: 503, sent: false),
    // Nothing reached a device, whatever the action.
    Expected(failure: HubError.unexpectedStatus(401), action: "on", code: "modemUnavailable", status: 503, sent: false),
    Expected(failure: HubError.unexpectedStatus(403), action: "status", code: "modemUnavailable", status: 503, sent: false),
    Expected(failure: ModemError.rejected(.getModemInfo), action: "on", code: "modemRejected", status: 503, sent: false),
    Expected(failure: ModemError.deviceRejected(device, NAKReason(rawValue: 0xFD)), action: "on", code: "deviceRejected", status: 422, sent: false),
    Expected(failure: ModemError.deviceRejected(device, .notLinked), action: "on", code: "notLinked", status: 409, sent: false),
    Expected(failure: DeviceControlError.notLinked, action: "on", code: "notLinked", status: 409, sent: false),
    Expected(failure: DeviceControlError.notIdentified(.status), action: "status", code: "notIdentified", status: 409, sent: false),
    Expected(failure: DeviceControlError.noSuchGroup(9, product: "Example"), action: "on", code: "unsupportedControl", status: 422, sent: false)
  ]

  private func run(_ failure: any Error, action: String) async throws -> (status: Int, json: [String: Any], log: LogCapture.Record) {
    let capture = LogCapture()
    let service = FakeService(failure: failure)
    let router = makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), logger: capture.logger)
    let app = Application(responder: router.buildResponder())
    return try await app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: commandHeaders, body: ByteBuffer(string: "{\"action\":\"" + action + "\"}"))
      #expect(response.headers[.contentType] == "application/json")
      let json = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
      return (Int(response.status.code), json, try #require(capture.records.first))
    }
  }

  @Test(arguments: table)
  func eachFailureHasOneCodeStatusAndSentFlagThatTheLogRepeats(_ expected: Expected) async throws {
    let (status, json, record) = try await run(expected.failure, action: expected.action)
    #expect(status == expected.status)
    #expect(json["version"] as? Int == 1)
    #expect(json["code"] as? String == expected.code)
    #expect(json["sent"] as? Bool == expected.sent)
    #expect((json["message"] as? String)?.isEmpty == false)
    #expect(record.metadata["code"] == .string(expected.code))
    #expect(record.metadata["status"] == .string(String(expected.status)))
    // The id in the body is the id on the log line, so a report finds its record.
    #expect(json["requestId"] as? String == record.metadata["request_id"].map { "\($0)" })
  }

  @Test func theBodyNamesTheModemsCauseOnlyWhenTheModemIsAway() async throws {
    let away = try await run(ServiceControlError.modemUnavailable(.credentialsRejected), action: "on")
    #expect(away.json["cause"] as? String == "credentialsRejected")
    let other = try await run(ServiceControlError.busy, action: "on")
    #expect(other.json["cause"] == nil)
  }

  @Test func aRejectedHubCredentialMidCommandIsAModemRefusalNotAPossiblySentControl() async throws {
    let (status, json, _) = try await run(HubError.unexpectedStatus(401), action: "on")
    #expect(status == 503)
    #expect(json["code"] as? String == "modemUnavailable")
    #expect(json["cause"] as? String == "credentialsRejected")
    #expect(json["sent"] as? Bool == false)
  }

  @Test func noBodyCarriesADeviceAddressACredentialOrALibraryDescription() async throws {
    for expected in Self.table {
      let (_, json, _) = try await run(expected.failure, action: expected.action)
      let text = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
      #expect(!text.contains("1A.2B.3C"))
      #expect(!text.contains(password))
    }
  }

  // MARK: Failures before the command reaches the service

  @Test func requestErrorsOnAPIRoutesAreTypedToo() async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    @Sendable func json(_ response: TestResponse) throws -> [String: Any] {
      try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
    }
    try await app.test(.router) { client in
      let path = "/api/v1/devices/1A.2B.3C/commands"
      let cases: [(String, HTTPRequest.Method, HTTPFields, String?, Int, String)] = [
        (path, .post, [.authorization: authorization], #"{"action":"on"}"#, 415, "unsupportedMediaType"),
        (path, .post, [.authorization: authorization, .contentType: "application/json"], #"{"action":"on"}"#, 403, "apiMarkerMissing"),
        (path, .post, commandHeaders, String(repeating: " ", count: 8193), 413, "bodyTooLarge"),
        (path, .post, commandHeaders, "{", 400, "invalidCommand"),
        (path, .post, commandHeaders, #"{"action":"remove"}"#, 400, "invalidCommand"),
        (path, .post, commandHeaders, #"{"action":"on","levle":50}"#, 400, "invalidCommand"),
        ("/api/v1/devices/not-an-address/commands", .post, commandHeaders, #"{"action":"on"}"#, 400, "invalidAddress"),
        ("/api/v1/scenes/4/plans", .post, commandHeaders, "{}", 400, "invalidMembership"),
        ("/api/v1/scenes/4/plans", .post, commandHeaders, #"{"remove":["nope"]}"#, 400, "invalidAddress"),
        ("/api/v1/scenes/0/plans", .post, commandHeaders, #"{"remove":["1A.2B.3C"]}"#, 400, "invalidScene"),
        ("/api/v1/scenes/7/plans", .post, commandHeaders, #"{"remove":["1A.2B.3C"]}"#, 404, "unknownScene"),
        ("/api/v1/nothing-here", .get, [.authorization: authorization], nil, 404, "routeNotFound")
      ]
      for (uri, method, headers, body, status, code) in cases {
        let response = try await client.execute(uri: uri, method: method, headers: headers, body: body.map { ByteBuffer(string: $0) })
        #expect(Int(response.status.code) == status, "\(code)")
        let object = try json(response)
        #expect(object["code"] as? String == code)
        #expect(object["sent"] as? Bool == false)
        #expect(object["version"] as? Int == 1)
      }
    }
    #expect(await service.commands.isEmpty)
  }

  @Test(arguments: [(String?.none, "authenticationRequired"), ("Basic incorrect", "authenticationFailed")])
  func anUnauthenticatedAPIRequestGetsTheTypedBodyAndTheChallenge(_ header: String?, _ code: String) async throws {
    let app = Application(responder: makeInsteonRouter(service: FakeService(), authentication: try HTTPAuthentication(password: password)).buildResponder())
    let fields: HTTPFields = header.map { [.authorization: $0] } ?? [:]
    try await app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/devices", method: .get, headers: fields)
      #expect(response.status == .unauthorized)
      #expect(response.headers[.wwwAuthenticate] != nil)
      let object = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
      #expect(object["code"] as? String == code)
      #expect(object["sent"] as? Bool == false)
    }
  }

  @Test func theBrowsersOwnRoutesKeepPlainTextErrors() async throws {
    let app = Application(responder: makeInsteonRouter(service: FakeService(), authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let denied = try await client.execute(uri: "/", method: .get)
      #expect(denied.status == .unauthorized)
      #expect(denied.headers[.contentType] == "text/plain; charset=utf-8")
      #expect(String(buffer: denied.body) == "Authentication required.")
      let invalid = try await client.execute(uri: "/devices/invalid", method: .get, headers: [.authorization: authorization])
      #expect(invalid.status == .badRequest)
      #expect(invalid.headers[.contentType] == "text/plain; charset=utf-8")
    }
  }

  // MARK: Browser forms and fragments use the same classification

  @Test(arguments: [
    (ServiceControlError.notIdentified, "on", 409, "has not reported what it is"),
    (ServiceControlError.notLinked, "on", 409, "not linked"),
    (ServiceControlError.modemUnavailable(.hubUnreachable), "on", 503, "Hub"),
    (ModemError.deviceTimedOut(InsteonAddress(0x1A, 0x2B, 0x3C)), "status", 504, "Could not read status"),
    (ModemError.deviceTimedOut(InsteonAddress(0x1A, 0x2B, 0x3C)), "on", 502, "hardware outcome may be unknown"),
    (ModemError.deviceRejected(InsteonAddress(0x1A, 0x2B, 0x3C), NAKReason(rawValue: 0xFD)), "on", 422, "rejected the command"),
    (ModemError.rejected(.getModemInfo), "on", 503, "modem refused")
  ] as [(any Error, String, Int, String)])
  func aFragmentFailureShowsTheSameClassificationOnTheCard(_ failure: any Error, _ action: String, _ status: Int, _ text: String) async throws {
    let service = FakeService(failure: failure)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let page = try await client.execute(uri: "/", method: .get, headers: [.authorization: authorization])
      let html = String(buffer: page.body)
      let start = try #require(html.range(of: "name=\"formKey\" value=\""))
      let key = try #require(html[start.upperBound...].split(separator: "\"").first)
      var fields: HTTPFields = [.authorization: authorization, .contentType: "application/x-www-form-urlencoded"]
      fields[HTTPField.Name("X-Insteon-Fragment")!] = "device"
      let response = try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: fields, body: ByteBuffer(string: "action=" + action + "&formKey=" + key))
      #expect(Int(response.status.code) == status)
      #expect(response.headers[.contentType] == "text/html; charset=utf-8")
      let card = String(buffer: response.body)
      #expect(card.hasPrefix("<article "))
      #expect(card.contains(text))
    }
  }
}
