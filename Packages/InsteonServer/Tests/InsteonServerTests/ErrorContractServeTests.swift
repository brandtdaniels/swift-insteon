import Foundation
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonService
import Testing
@testable import InsteonServerSupport

/// What each failure reports through the real server, router and service over a scripted modem
/// connection: the code, the status, and whether a command may have reached a device.
@Suite(.timeLimit(.minutes(1)))
struct ErrorContractServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  private func command(_ server: RunningServer, _ action: String, to path: String = "/api/v1/devices/1A.2B.3C/commands") async throws -> (status: Int, json: [String: Any]) {
    try await server.request(path, method: "POST", body: "{\"action\":\"" + action + "\"}", password: gatewayPassword)
  }

  private func expect(_ result: (status: Int, json: [String: Any]), _ status: Int, _ code: String, sent: Bool, cause: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(result.status == status, sourceLocation: sourceLocation)
    #expect(result.json["version"] as? Int == 1, sourceLocation: sourceLocation)
    #expect(result.json["code"] as? String == code, sourceLocation: sourceLocation)
    #expect(result.json["sent"] as? Bool == sent, sourceLocation: sourceLocation)
    #expect(result.json["cause"] as? String == cause, sourceLocation: sourceLocation)
    #expect((result.json["message"] as? String)?.isEmpty == false, sourceLocation: sourceLocation)
  }

  /// Starts a server connected to a modem the test controls.
  private func connected(identified: Bool = true) async throws -> (server: RunningServer, link: HubLink) {
    let link = HubLink()
    let server = try await start(try scratch(identified: identified), openModem: opener(ScriptedHubOpener([.connect(link)])))
    _ = await server.code("modem_connected")
    return (server, link)
  }

  // MARK: Nothing was sent

  @Test func wrongHubCredentialsAreAModemRefusalWithTheCauseAndNothingSent() async throws {
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(HubError.unexpectedStatus(401))])))
    _ = await server.code("hub_credentials_rejected")
    expect(try await command(server, "on"), 503, "modemUnavailable", sent: false, cause: "credentialsRejected")
    await server.stop()
  }

  @Test func anUnreachableHubIsAModemRefusalWithTheCauseAndNothingSent() async throws {
    let server = try await start(try scratch(), openModem: opener(ScriptedHubOpener([.fail(HubStoppedAnswering(underlyingError: URLError(.timedOut)))])))
    _ = await server.code("hub_unreachable")
    expect(try await command(server, "status"), 503, "modemUnavailable", sent: false, cause: "hubUnreachable")
    await server.stop()
  }

  @Test func aCommandToADeviceTheServiceDoesNotKnowIsNotFound() async throws {
    let (server, link) = try await connected()
    expect(try await command(server, "on", to: "/api/v1/devices/AA.BB.CC/commands"), 404, "unknownDevice", sent: false)
    #expect(await link.modem.levels.isEmpty)
    await server.stop()
  }

  @Test(arguments: [(["--hub", "192.168.1.20"], "hubUnreachable", "The Hub is not answering"), (["--serial", "/dev/example-modem"], "modemUnreachable", "The modem is not answering")])
  func aModemThatDoesNotAnswerIsNamedForItsTarget(_ target: [String], _ cause: String, _ wording: String) async throws {
    let server = try await start(try scratch(), extra: target, openModem: opener(ScriptedHubOpener([.fail(ModemError.timedOut(.getModemInfo))])))
    _ = await server.code(cause == "hubUnreachable" ? "hub_unreachable" : "modem_unreachable")
    let refused = try await command(server, "on")
    expect(refused, 503, "modemUnavailable", sent: false, cause: cause)
    #expect((refused.json["message"] as? String)?.hasPrefix(wording) == true)
    let health = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect((health.json["modem"] as? [String: Any])?["cause"] as? String == cause)
    await server.stop()
  }

  @Test func aMalformedAddressIsABadRequest() async throws {
    let (server, _) = try await connected()
    expect(try await command(server, "on", to: "/api/v1/devices/not-an-address/commands"), 400, "invalidAddress", sent: false)
    await server.stop()
  }

  @Test func aSecondCommandWhileOneRunsIsBusyAndNothingIsQueued() async throws {
    let (server, link) = try await connected()
    let arrivals = await link.modem.hold()
    let password = gatewayPassword
    let first = Task { try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, password: password).status }
    var waiting = arrivals.makeAsyncIterator()
    _ = await waiting.next()
    expect(try await command(server, "off"), 409, "busy", sent: false)
    await link.modem.release()
    #expect(try await first.value == 200)
    #expect(await link.modem.levels[device] == 0xFF)
    await server.stop()
  }

  @Test func aDeviceThatIsNotLinkedToTheModemRejectsItAndNothingChanges() async throws {
    let (server, link) = try await connected(identified: false)
    await link.modem.fail(device, with: ModemError.deviceRejected(device, .notLinked))
    expect(try await command(server, "on"), 409, "notLinked", sent: false)
    expect(try await command(server, "status"), 409, "notLinked", sent: false)
    #expect(await link.modem.levels.isEmpty)
    await server.stop()
  }

  // MARK: The identity is unknown

  @Test func anUnidentifiedDeviceThatDoesNotAnswerIsNotIdentifiedForControlsAndForReads() async throws {
    let (server, link) = try await connected(identified: false)
    await link.modem.fail(device, with: ModemError.deviceTimedOut(device))
    // A control is not "unsupported": the device's type is simply unknown.
    expect(try await command(server, "on"), 409, "notIdentified", sent: false)
    expect(try await command(server, "off"), 409, "notIdentified", sent: false)
    // A read of an unidentified device is not a control that may have been sent.
    expect(try await command(server, "status"), 409, "notIdentified", sent: false)
    #expect(await link.modem.levels.isEmpty)
    await server.stop()
  }

  // MARK: A command was sent

  @Test func aControlThatTimesOutMayHaveReachedTheDevice() async throws {
    let (server, link) = try await connected()
    await link.modem.fail(device, with: ModemError.deviceTimedOut(device))
    expect(try await command(server, "on"), 502, "outcomeUnknown", sent: true)
    await server.stop()
  }

  @Test func aReadThatTimesOutChangedNothingAndIsSafeToRepeat() async throws {
    let (server, link) = try await connected()
    await link.modem.fail(device, with: ModemError.deviceTimedOut(device))
    expect(try await command(server, "status"), 504, "deviceNotAnswering", sent: false)
    expect(try await command(server, "identify"), 504, "deviceNotAnswering", sent: false)
    await server.stop()
  }

  @Test func aDeviceThatNaksAControlRejectedItAndNothingChanged() async throws {
    let (server, link) = try await connected()
    await link.modem.fail(device, with: ModemError.deviceRejected(device, NAKReason(rawValue: 0xFD)))
    expect(try await command(server, "on"), 422, "deviceRejected", sent: false)
    await server.stop()
  }

  @Test func aHubCredentialRejectedWhileACommandRunsIsARefusalNotAPossiblySentControl() async throws {
    let (server, link) = try await connected()
    await link.modem.fail(device, with: HubError.unexpectedStatus(401))
    expect(try await command(server, "on"), 503, "modemUnavailable", sent: false, cause: "credentialsRejected")
    await server.stop()
  }

  // MARK: The log and the response agree

  @Test func theLogRecordCarriesTheCodeAndTheRequestIdTheResponseReports() async throws {
    let (server, link) = try await connected()
    await link.modem.fail(device, with: ModemError.deviceTimedOut(device))
    let result = try await command(server, "on")
    let id = try #require(result.json["requestId"] as? String)
    let record = try #require(await server.record { $0.metadata["request_id"].map { "\($0)" } == id })
    #expect(record.metadata["code"] == "outcomeUnknown")
    #expect(record.metadata["status"] == "502")
    await server.stop()
  }

  @Test func aWrongGatewayPasswordIsATypedUnauthorizedAndNeverReachesTheService() async throws {
    let (server, link) = try await connected()
    let result = try await server.request("/api/v1/devices/1A.2B.3C/commands", method: "POST", body: #"{"action":"on"}"#, password: "wrong")
    expect(result, 401, "authenticationFailed", sent: false)
    #expect(await link.modem.levels.isEmpty)
    await server.stop()
  }
}
