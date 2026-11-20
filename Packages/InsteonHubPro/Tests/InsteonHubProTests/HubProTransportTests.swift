import Foundation
import InsteonHubPro
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct HubProTransportTests {

  let lamp = InsteonAddress(0x11, 0x22, 0x33)

  func transport(_ http: RoutedHTTPClient) -> HubProTransport {

    HubProTransport(host: HubProUnit.host, httpClient: http)

  }

  // MARK: - Reads

  @Test func listsTheDevicesAndMarksItsOwnModem() async throws {

    let http = RoutedHTTPClient(["GET /insteon/list": answerJSON(HubProUnit.list)])

    let devices = try await transport(http).devices()

    #expect(devices == [
      HubProListedDevice(address: InsteonAddress(0xAA, 0xBB, 0xCC), name: "(PLM)", deviceType: "Hub Pro", isModem: true),
      HubProListedDevice(address: lamp, name: "Example Dimmer", deviceType: "Example Dimmer", isModem: false),
    ])
    #expect(await http.sent == ["GET /insteon/list"])

  }

  @Test func readsEveryDevicesOnLevel() async throws {

    let http = RoutedHTTPClient(["GET /insteon/status": answerJSON(HubProUnit.status)])

    #expect(try await transport(http).levels() == [lamp: 0])

  }

  @Test func describesADevice() async throws {

    let http = RoutedHTTPClient(["GET /insteon/describe?device=11.22.33": answerJSON(HubProUnit.describe)])

    let description = try await transport(http).describe(lamp)

    #expect(description.address == lamp)
    #expect(description.name == "Example Dimmer")
    #expect(description.deviceType == "Example Dimmer")
    #expect(description.category == 1)
    #expect(description.subcategory == 14)
    #expect(description.firmwareVersion == 59)
    #expect(description.sku == "9101X1")
    #expect(description.commandNames.contains("On"))
    #expect(description.parameters(of: "On") == ["OnLevel"])
    #expect(description.offers(.statusRequest))
    #expect(description.offers(.on(level: 255)))
    #expect(!description.offers(.ping))
    #expect(!description.offers(.fastOff))

  }

  @Test func readsTheSettings() async throws {

    let settings = #"{"time":"2026-10-28 05:00:00","network":{"address":"192.0.2.10"},"version":{"config":{"version":"5.0.6"},"server":{"version":"1.0.8.9"}}}"#
    let http = RoutedHTTPClient(["GET /settings": answerJSON(settings)])

    #expect(try await transport(http).settings().version.config.version == "5.0.6")

  }

  @Test func reportsAnAnswerItCantReadAsMalformed() async {

    let http = RoutedHTTPClient(["GET /insteon/list": answerJSON(#"{"nothing":1}"#), "GET /insteon/status": answerJSON("[1]")])

    await #expect(throws: HubProError.malformedResponse) { try await transport(http).devices() }
    await #expect(throws: HubProError.malformedResponse) { try await transport(http).levels() }

  }

  // MARK: - Commands

  @Test func readsADevicesStatusWithStatusRequest() async throws {

    let http = RoutedHTTPClient(["GET /insteon/command?device=11.22.33&key=StatusRequest": answerJSON(HubProUnit.statusRequest)])

    let result = try await transport(http).perform(.statusRequest, on: lamp)

    #expect(result == HubProCommandResult(onLevel: 0, linkDelta: 5))

  }

  @Test func turnsADeviceOnWithALevelAndOff() async throws {

    let http = RoutedHTTPClient([
      "GET /insteon/command?device=11.22.33&key=On&OnLevel=255": answerJSON(HubProUnit.succeeded),
      "GET /insteon/command?device=11.22.33&key=Off": answerJSON(HubProUnit.succeeded),
    ])
    let unit = transport(http)

    let on = try await unit.perform(.on(level: 255), on: lamp)
    let off = try await unit.perform(.off, on: lamp)

    #expect(on == HubProCommandResult(onLevel: nil, linkDelta: nil))
    #expect(off == on)
    #expect(await http.sent == ["GET /insteon/command?device=11.22.33&key=On&OnLevel=255", "GET /insteon/command?device=11.22.33&key=Off"])

  }

  @Test func sendsNoLevelWhenTheCommandHasNone() async throws {

    let http = RoutedHTTPClient(["GET /insteon/command?device=11.22.33&key=FastOn": answerJSON(HubProUnit.succeeded)])

    _ = try await transport(http).perform(.fastOn(level: nil), on: lamp)

    #expect(await http.sent == ["GET /insteon/command?device=11.22.33&key=FastOn"])

  }

  @Test func reportsADeviceTheUnitDoesNotKnow() async {

    let http = RoutedHTTPClient(["GET /insteon/command?device=11.22.33&key=Off": answerJSON(HubProUnit.unknownDevice)])

    await #expect(throws: HubProControlError.unknownDevice(lamp)) { try await transport(http).perform(.off, on: lamp) }

  }

  @Test func reportsACommandTheDeviceDoesNotSupport() async {

    let http = RoutedHTTPClient(["GET /insteon/command?device=11.22.33&key=Off": answerJSON(HubProUnit.unsupportedKey)])

    await #expect(throws: HubProControlError.notSupported(command: "Off", device: lamp)) { try await transport(http).perform(.off, on: lamp) }

  }

  @Test func reportsAnyOtherErrorAsRejected() async {

    let http = RoutedHTTPClient(["GET /insteon/command?device=11.22.33&key=Off": answerJSON(HubProUnit.missingParameters)])

    await #expect(throws: HubProError.rejected("The following required parameters were not specified: 'device, key'")) {
      try await transport(http).perform(.off, on: lamp)
    }

  }

  @Test(arguments: [#"{"result":"failed"}"#, #"{"result":"pending"}"#, #"{"command":"Off"}"#, "{}"])
  func reportsAnyResultButSuccessfulAsNotConfirmed(body: String) async {

    let http = RoutedHTTPClient(["GET /insteon/command?device=11.22.33&key=Off": answerJSON(body)])

    await #expect(throws: HubProControlError.notConfirmed) { try await transport(http).perform(.off, on: lamp) }

  }

  // MARK: - Safety

  @Test(arguments: ["WriteLink", "ClearLink", "LinkPlm", "EnterLinkMode", "RemoveDeviceComplete", "SetX10Info"])
  func neverBuildsACommandThatChangesLinks(key: String) {

    #expect(HubProCommand(key: key) == nil)
    #expect(HubProCommand.refusedKeys.contains(key))
    #expect(!HubProCommand.allowedKeys.contains(key))

  }

  @Test func allowsOnlyTheKeysItNames() {

    #expect(HubProCommand.allowedKeys == ["StatusRequest", "Ping", "IDRequest", "On", "Off", "FastOn", "FastOff", "Beep"])

    for key in HubProCommand.allowedKeys {

      #expect(HubProCommand(key: key)?.key == key)

    }

    #expect(HubProCommand(key: "On")?.level == 255)
    #expect(HubProCommand(key: "Off")?.level == nil)
    #expect(HubProCommand(key: "Anything") == nil)

  }

  @Test func reachesNoPathButTheReadsAndTheCommand() async throws {

    let http = RoutedHTTPClient([
      "GET /settings": answerJSON(#"{"time":"t","network":{"address":"a"},"version":{"config":{"version":"1"},"server":{"version":"1"}}}"#),
      "GET /insteon/list": answerJSON(HubProUnit.list),
      "GET /insteon/status": answerJSON(HubProUnit.status),
      "GET /insteon/describe?device=11.22.33": answerJSON(HubProUnit.describe),
    ])
    let unit = transport(http)

    _ = try await unit.settings()
    _ = try await unit.devices()
    _ = try await unit.levels()
    _ = try await unit.describe(lamp)

    for command in [HubProCommand.statusRequest, .ping, .idRequest, .on(level: 1), .off, .fastOn(level: 1), .fastOff, .beep] {

      _ = try? await unit.perform(command, on: lamp)

    }

    for request in await http.sent {

      let path = request.split(separator: " ")[1].split(separator: "?")[0]

      #expect(["/settings", "/insteon/list", "/insteon/status", "/insteon/describe", "/insteon/command"].contains(String(path)), "\(request)")
      #expect(!request.contains("/add") && !request.contains("/remove") && !request.contains("/update"))

    }

  }

  // MARK: - One request at a time

  @Test func sendsOneRequestAtATime() async throws {

    let http = RoutedHTTPClient(["GET /insteon/list": answerJSON(HubProUnit.list), "GET /insteon/status": answerJSON(HubProUnit.status)])
    let unit = transport(http)

    await http.holdNextRequest()

    async let first = unit.devices()
    await http.waitForRequests(1)

    async let second = unit.levels()

    // The second waits while the first is held: only the first has been sent.
    await Task.yield()
    #expect(await http.sent == ["GET /insteon/list"])

    await http.release()

    _ = try await first
    _ = try await second

    #expect(await http.sent == ["GET /insteon/list", "GET /insteon/status"])

  }

  // MARK: - GET then POST

  @Test(arguments: [404, 405])
  func asksAgainWithAPostWhenAGetIsNotAllowedAndRemembersIt(status: Int) async throws {

    let http = RoutedHTTPClient([
      "GET /insteon/list": answerJSON("", status: status),
      "POST /insteon/list": answerJSON(HubProUnit.list),
      "POST /insteon/status": answerJSON(HubProUnit.status),
    ])
    let unit = transport(http)

    _ = try await unit.devices()
    _ = try await unit.levels()

    #expect(await http.sent == ["GET /insteon/list", "POST /insteon/list", "POST /insteon/status"])

  }

  @Test func doesNotAskAgainForAnotherStatus() async {

    let http = RoutedHTTPClient(["GET /insteon/list": answerJSON("", status: 500), "POST /insteon/list": answerJSON(HubProUnit.list)])

    await #expect(throws: HubProError.unexpectedStatus(500)) { try await transport(http).devices() }
    #expect(await http.sent == ["GET /insteon/list"])

  }

  @Test func asksAgainWithAPostForACommandToo() async throws {

    let http = RoutedHTTPClient([
      "GET /insteon/command?device=11.22.33&key=Off": answerJSON("", status: 405),
      "POST /insteon/command?device=11.22.33&key=Off": answerJSON(HubProUnit.succeeded),
    ])

    _ = try await transport(http).perform(.off, on: lamp)

    #expect(await http.sent == ["GET /insteon/command?device=11.22.33&key=Off", "POST /insteon/command?device=11.22.33&key=Off"])

  }

  // MARK: - Deadline

  @Test func limitsEachRequestToTheTimeout() async throws {

    let http = StubHTTPClient(response: answerJSON(HubProUnit.status))

    _ = try await HubProTransport(host: HubProUnit.host, httpClient: http, timeout: .seconds(7)).levels()
    _ = try await HubProTransport(host: HubProUnit.host, httpClient: http).levels()

    let timeouts = await http.requests.map(\.timeoutInterval)

    #expect(timeouts == [7, 15])

  }

}
