import Foundation
import InsteonDeviceCatalog
import InsteonHubPro
import InsteonModem
import InsteonNetworking
import InsteonProtocol
import InsteonTestSupport
import Testing
@testable import InsteonCore

/// A network whose devices are reached through a Hub Pro's local HTTP interface, driven with the
/// unit's observed answers and an invented catalog.
@Suite(.timeLimit(.minutes(1)))
struct HubProNetworkTests {

  static let dimmer = InsteonAddress(0x3A, 0x4B, 0x01)
  static let relay = InsteonAddress(0x3A, 0x4B, 0x02)
  static let stranger = InsteonAddress(0x3A, 0x4B, 0x07)
  static let modem = "AA.BB.CC"

  static let commandsOfADimmer: [(String, [String])] = [("Beep", []), ("On", ["OnLevel"]), ("Off", []), ("StatusRequest", []), ("WriteLink", [])]

  static func listing(_ devices: [(String, String)]) -> String {

    let entries = [#"{"location":"","name":"(PLM)","device":"\#(modem)","deviceType":"Hub Pro"}"#]
      + devices.map { #"{"location":"","name":"\#($0.1)","device":"\#($0.0)","deviceType":"\#($0.1)"}"# }

    return "[\(entries.joined(separator: ","))]"

  }

  static func levels(_ levels: [(String, Int)]) -> String {

    "[\(levels.map { #"{"OnLevel":\#($0.1),"device":"\#($0.0)"}"# }.joined(separator: ","))]"

  }

  static func describe(_ address: String, _ identity: ReportedIdentity, commands: [(String, [String])] = commandsOfADimmer) -> String {

    HubProUnit.describe(device: address, category: Int(identity.category.rawValue), subcategory: Int(identity.subcategory.rawValue), firmware: Int(identity.firmwareVersion?.rawValue ?? 0), commands: commands)

  }

  /// A unit with one dimmer at 3A.4B.01 that lists every command a dimmer is sent.
  static func unit(
    extra: [String: String] = [:],
    commands: [(String, [String])] = commandsOfADimmer
  ) -> RoutedHTTPClient {

    var routes = [
      "GET /settings": answerJSON(HubProUnit.settings),
      "GET /insteon/list": answerJSON(listing([("3A.4B.01", "Example Dimmer")])),
      "GET /insteon/status": answerJSON(levels([("3A.4B.01", 0)])),
      "GET /insteon/describe?device=3A.4B.01": answerJSON(describe("3A.4B.01", ControlExample.dimmerIdentity, commands: commands)),
    ]

    for (route, body) in extra {

      routes[route] = answerJSON(body)

    }

    return RoutedHTTPClient(routes)

  }

  func network(_ http: RoutedHTTPClient, clock: any Clock<Duration> = TestClock(), listRefreshPolls: Int = 12) -> HubProNetwork {

    HubProNetwork(
      transport: HubProTransport(host: HubProUnit.host, httpClient: http),
      catalog: ControlExample.catalog,
      clock: clock,
      listRefreshPolls: listRefreshPolls,
      now: { Date(timeIntervalSince1970: 1_000) }
    )

  }

  func opened(_ http: RoutedHTTPClient) async throws -> HubProNetwork {

    let network = network(http)

    try await network.open()

    return network

  }

  // MARK: - Connect and list

  @Test func readsTheSettingsAndTheListThenDescribesEachDeviceButTheModem() async throws {

    let http = Self.unit()

    let network = try await opened(http)

    #expect(await http.sent == ["GET /settings", "GET /insteon/list", "GET /insteon/describe?device=3A.4B.01", "GET /insteon/status"])
    #expect(await network.devices().map(\.address) == [Self.dimmer])

    let known = try #require(await network.registry.device(Self.dimmer))

    #expect(known.identity == ControlExample.dimmerIdentity)
    #expect(known.info.displayName == "Example Dimmer 9101")

    let description = try #require(await network.description(of: Self.dimmer))

    #expect(description.sku == "9101X1")

  }

  @Test func keepsTheLevelsItReadsInItsSnapshot() async throws {

    let http = Self.unit(extra: ["GET /insteon/status": Self.levels([("3A.4B.01", 255)])])

    let snapshot = try await opened(http).snapshot()

    #expect(snapshot.devices[Self.dimmer]?.level == 255)
    #expect(snapshot.devices[Self.dimmer]?.lastSeen == Date(timeIntervalSince1970: 1_000))
    #expect(snapshot.registry.identities[Self.dimmer] == ControlExample.dimmerIdentity)

  }

  @Test func followsTheUnitsListWhenItChanges() async throws {

    let http = Self.unit()
    let network = try await opened(http)

    await http.answer("GET /insteon/list", with: answerJSON(Self.listing([("3A.4B.02", "Example Relay")])))
    await http.answer("GET /insteon/describe?device=3A.4B.02", with: answerJSON(Self.describe("3A.4B.02", ControlExample.relayIdentity)))

    try await network.refreshDevices()

    #expect(await network.devices().map(\.address) == [Self.relay])
    #expect(await network.registry.device(Self.dimmer) == nil)
    #expect(await network.registry.device(Self.relay)?.identity == ControlExample.relayIdentity)
    #expect(await network.snapshot().devices[Self.dimmer] == nil)

  }

  @Test func neverAsksTheUnitToAddOrRemoveADevice() async throws {

    let http = Self.unit(extra: [
      "GET /insteon/command?device=3A.4B.01&key=On&OnLevel=\(LightLevel.level(percent: 50))": HubProUnit.succeeded,
      "GET /insteon/command?device=3A.4B.01&key=Off": HubProUnit.succeeded,
    ])
    let network = try await opened(http)

    try await network.refreshDevices()
    _ = try await network.device(Self.dimmer).turnOn(level: 50)
    try await network.device(Self.dimmer).turnOff()

    for request in await http.sent {

      #expect(!request.contains("/add") && !request.contains("/remove") && !request.contains("/update"), "\(request)")

    }

  }

  // MARK: - Read

  @Test func readsAStatusWithStatusRequestAndTheDevicesReply() async throws {

    let http = Self.unit(extra: ["GET /insteon/command?device=3A.4B.01&key=StatusRequest": HubProUnit.statusRequest.replacingOccurrences(of: #""OnLevel":0"#, with: #""OnLevel":255"#)])
    let network = try await opened(http)

    let status = try await network.device(Self.dimmer).status()

    #expect(status.value == 255)
    #expect(status.isOn)
    #expect(status.percent == 100)
    #expect(status.allLinkDatabaseDelta == 5)
    #expect(await http.sent.last == "GET /insteon/command?device=3A.4B.01&key=StatusRequest")
    #expect(await network.snapshot().devices[Self.dimmer]?.level == 255)

  }

  @Test func pingsADeviceTheUnitListsPingFor() async throws {

    let http = Self.unit(extra: ["GET /insteon/command?device=3A.4B.01&key=Ping": HubProUnit.succeeded], commands: Self.commandsOfADimmer + [("Ping", [])])
    let network = try await opened(http)

    try await network.device(Self.dimmer).ping()

    #expect(await http.sent.last == "GET /insteon/command?device=3A.4B.01&key=Ping")

  }

  @Test func refusesToPingADeviceTheUnitDoesNotListPingFor() async throws {

    let http = Self.unit()
    let network = try await opened(http)
    let before = await http.sent.count

    await #expect(throws: DeviceControlError.unsupported(.status, product: "Example Dimmer 9101")) {
      try await network.device(Self.dimmer).ping()
    }

    #expect(await http.sent.count == before)

  }

  // MARK: - Actuate

  @Test func turnsOnWithTheLevelOnTheUnitsScaleAndOff() async throws {

    let level = LightLevel.level(percent: 50)
    let http = Self.unit(extra: [
      "GET /insteon/command?device=3A.4B.01&key=On&OnLevel=\(level)": HubProUnit.succeeded,
      "GET /insteon/command?device=3A.4B.01&key=Off": HubProUnit.succeeded,
    ])
    let network = try await opened(http)
    let lamp = network.device(Self.dimmer)

    let result = try await lamp.turnOn(level: 50)
    let afterOn = await network.snapshot().devices[Self.dimmer]?.level
    try await lamp.turnOff()
    let afterOff = await network.snapshot().devices[Self.dimmer]?.level

    #expect(result.level == 50)
    #expect(result.ignoredLevel == nil)
    #expect(afterOn == level)
    #expect(afterOff == 0)
    #expect(await http.sent.suffix(2) == ["GET /insteon/command?device=3A.4B.01&key=On&OnLevel=\(level)", "GET /insteon/command?device=3A.4B.01&key=Off"])

  }

  @Test func turnsFullyOnWithoutALevel() async throws {

    let http = Self.unit(extra: ["GET /insteon/command?device=3A.4B.01&key=On&OnLevel=255": HubProUnit.succeeded])

    _ = try await opened(http).device(Self.dimmer).turnOn(level: nil)

    #expect(await http.sent.last == "GET /insteon/command?device=3A.4B.01&key=On&OnLevel=255")

  }

  @Test func sendsFastOnAndFastOffOnlyWhenTheUnitListsThem() async throws {

    let listed = Self.commandsOfADimmer + [("FastOn", ["OnLevel"]), ("FastOff", [])]
    let http = Self.unit(
      extra: [
        "GET /insteon/command?device=3A.4B.01&key=FastOn&OnLevel=255": HubProUnit.succeeded,
        "GET /insteon/command?device=3A.4B.01&key=FastOff": HubProUnit.succeeded,
      ],
      commands: listed
    )
    let lamp = try await opened(http).device(Self.dimmer)

    _ = try await lamp.turnOnFast(level: nil)
    _ = try await lamp.turnOffFast()

    #expect(await http.sent.suffix(2) == ["GET /insteon/command?device=3A.4B.01&key=FastOn&OnLevel=255", "GET /insteon/command?device=3A.4B.01&key=FastOff"])

  }

  @Test func refusesACommandTheUnitDoesNotListBeforeSendingAnything() async throws {

    let http = Self.unit()
    let lamp = try await opened(http).device(Self.dimmer)
    let before = await http.sent.count
    let product = "Example Dimmer 9101"

    await #expect(throws: DeviceControlError.unsupported(.turnOnFast, product: product)) { _ = try await lamp.turnOnFast(level: nil) }
    await #expect(throws: DeviceControlError.unsupported(.turnOffFast, product: product)) { _ = try await lamp.turnOffFast() }

    #expect(await http.sent.count == before)

  }

  @Test func beepsOnlyWhenTheUnitListsBeep() async throws {

    let http = Self.unit(extra: ["GET /insteon/command?device=3A.4B.01&key=Beep": HubProUnit.succeeded])
    let lamp = try await opened(http).device(Self.dimmer)

    let result = try await lamp.beep()

    #expect(result.isListed)
    #expect(await http.sent.last == "GET /insteon/command?device=3A.4B.01&key=Beep")

    let silent = Self.unit(commands: [("On", ["OnLevel"]), ("Off", []), ("StatusRequest", [])])
    let mute = try await opened(silent).device(Self.dimmer)
    let before = await silent.sent.count

    await #expect(throws: DeviceControlError.unsupported(.beep, product: "Example Dimmer 9101")) { _ = try await mute.beep() }
    #expect(await silent.sent.count == before)

  }

  @Test func reportsAnOutcomeThatCantBeKnownWhenTheUnitDoesNotConfirmItAndSendsItOnce() async throws {

    let http = Self.unit(extra: ["GET /insteon/command?device=3A.4B.01&key=Off": #"{"result":"failed"}"#])
    let lamp = try await opened(http).device(Self.dimmer)
    let before = await http.sent.count

    await #expect(throws: ModemError.deviceTimedOut(Self.dimmer)) { try await lamp.turnOff() }

    #expect(await http.sent.count == before + 1)

  }

  @Test func reportsAnOutcomeThatCantBeKnownWhenTheUnitDoesNotAnswerAndSendsItOnce() async throws {

    // No route for Off, so the stub answers 404 to the GET and to the POST asked for after it.
    let http = Self.unit()
    let lamp = try await opened(http).device(Self.dimmer)
    let before = await http.sent.count

    await #expect(throws: ModemError.deviceTimedOut(Self.dimmer)) { try await lamp.turnOff() }

    #expect(await http.sent.count == before + 2)

  }

  @Test func readsTheCapabilitiesFromTheCatalog() async throws {

    let capabilities = try await opened(Self.unit()).device(Self.dimmer).capabilities()

    #expect(capabilities.productName == "Example Dimmer 9101")
    #expect(capabilities.isIdentified)
    #expect(capabilities.canDim)
    #expect(capabilities.canTurnOnAndOff)

  }

  // MARK: - A device the catalog does not know

  @Test func takesOnlyReadsForADeviceTheCatalogDoesNotKnow() async throws {

    let http = RoutedHTTPClient([
      "GET /settings": answerJSON(HubProUnit.settings),
      "GET /insteon/list": answerJSON(Self.listing([("3A.4B.07", "Mystery")])),
      "GET /insteon/status": answerJSON(Self.levels([("3A.4B.07", 0)])),
      "GET /insteon/describe?device=3A.4B.07": answerJSON(HubProUnit.describe(device: "3A.4B.07", category: 7, subcategory: 85, firmware: 69, commands: Self.commandsOfADimmer)),
      "GET /insteon/command?device=3A.4B.07&key=StatusRequest": answerJSON(HubProUnit.statusRequest),
    ])
    let network = try await opened(http)
    let device = network.device(Self.stranger)
    let before = await http.sent.count

    let status = try await device.status()

    #expect(status.reading == .raw)
    await #expect(throws: DeviceControlError.self) { _ = try await device.turnOn(level: nil) }
    #expect(await http.sent.count == before + 1)

  }

  // MARK: - Events

  @Test func publishesAStatusChangeWhenAnOnLevelChanges() async throws {

    let clock = TestClock()
    let http = Self.unit()
    let network = network(http, clock: clock)
    try await network.open()

    let first = Task { try await network.changes().first { _ in true } }

    await clock.waitForSleeper(until: .seconds(5))
    await http.answer("GET /insteon/status", with: answerJSON(Self.levels([("3A.4B.01", 128)])))
    clock.advance(by: .seconds(5))

    #expect(try await first.value == .statusChanged(Self.dimmer))
    #expect(await network.snapshot().devices[Self.dimmer]?.level == 128)

  }

  @Test func staysSilentWhileLevelsHoldAndPollsOneRequestAtATime() async throws {

    let clock = TestClock()
    let http = Self.unit()
    let network = network(http, clock: clock)
    try await network.open()
    let opened = await http.sent.count

    let first = Task { try await network.changes().first { _ in true } }

    for step in 1...3 {

      await clock.waitForSleeper(until: .seconds(5 * step))
      clock.advance(by: .seconds(5))

    }

    await clock.waitForSleeper(until: .seconds(20))
    await http.answer("GET /insteon/status", with: answerJSON(Self.levels([("3A.4B.01", 1)])))
    clock.advance(by: .seconds(5))

    _ = try await first.value

    #expect(await http.sent.dropFirst(opened).allSatisfy { $0 == "GET /insteon/status" })
    #expect(await http.sent.count == opened + 4)

  }

  @Test func refreshesTheListOnEveryNthPoll() async throws {

    let clock = TestClock()
    let http = Self.unit()
    let network = network(http, clock: clock, listRefreshPolls: 2)
    try await network.open()
    let opened = await http.sent.count

    let first = Task { try await network.changes().first { _ in true } }

    await clock.waitForSleeper(until: .seconds(5))
    clock.advance(by: .seconds(5))
    await clock.waitForSleeper(until: .seconds(10))
    await http.answer("GET /insteon/status", with: answerJSON(Self.levels([("3A.4B.01", 9)])))
    clock.advance(by: .seconds(5))

    _ = try await first.value

    let polled = await http.sent.dropFirst(opened)

    #expect(Array(polled).filter { $0 == "GET /insteon/list" }.count == 1)
    #expect(Array(polled).filter { $0 == "GET /insteon/status" }.count == 2)

  }

  @Test func doesNotReportADeviceTheFirstTimeItsLevelIsRead() async throws {

    let clock = TestClock()
    let http = Self.unit()
    let network = network(http, clock: clock, listRefreshPolls: 1)
    try await network.open()

    let first = Task { try await network.changes().first { _ in true } }

    // The unit lists a second device, whose level the next poll reads for the first time.
    await http.answer("GET /insteon/list", with: answerJSON(Self.listing([("3A.4B.01", "Example Dimmer"), ("3A.4B.02", "Example Relay")])))
    await http.answer("GET /insteon/describe?device=3A.4B.02", with: answerJSON(Self.describe("3A.4B.02", ControlExample.relayIdentity)))
    await http.answer("GET /insteon/status", with: answerJSON(Self.levels([("3A.4B.01", 0), ("3A.4B.02", 77)])))
    await clock.waitForSleeper(until: .seconds(5))
    clock.advance(by: .seconds(5))

    // Only the dimmer's change is reported, at the poll after.
    await clock.waitForSleeper(until: .seconds(10))
    await http.answer("GET /insteon/status", with: answerJSON(Self.levels([("3A.4B.01", 5), ("3A.4B.02", 77)])))
    clock.advance(by: .seconds(5))

    #expect(try await first.value == .statusChanged(Self.dimmer))

  }

  @Test func endsTheChangesWithTheErrorWhenAPollFails() async throws {

    let clock = TestClock()
    let http = Self.unit()
    let network = network(http, clock: clock)
    try await network.open()

    let ended = Task { () async -> (any Error)? in

      do { _ = try await network.changes().first { _ in true } } catch { return error }

      return nil

    }

    await clock.waitForSleeper(until: .seconds(5))
    await http.answer("GET /insteon/status", with: HTTPResponse(statusCode: 500))
    clock.advance(by: .seconds(5))

    #expect(await ended.value as? HubProError == .unexpectedStatus(500))

  }

  @Test func keepsThePollIntervalAtOrAboveItsFloor() async throws {

    let clock = IntervalClock()
    let http = Self.unit()
    let network = HubProNetwork(transport: HubProTransport(host: HubProUnit.host, httpClient: http), catalog: ControlExample.catalog, pollInterval: .milliseconds(10), clock: clock)
    try await network.open()

    let first = Task { try await network.changes().first { _ in true } }
    var waits = clock.requested.makeAsyncIterator()

    #expect(await waits.next() == HubProNetwork.minimumPollInterval)

    first.cancel()
    _ = try? await first.value

    #expect(HubProNetwork.minimumPollInterval == .seconds(2))
    #expect(HubProNetwork.defaultPollInterval == .seconds(5))

  }

  @Test func waitsTheIntervalItIsGivenAboveTheFloor() async throws {

    let clock = IntervalClock()
    let http = Self.unit()
    let network = HubProNetwork(transport: HubProTransport(host: HubProUnit.host, httpClient: http), catalog: ControlExample.catalog, pollInterval: .seconds(9), clock: clock)
    try await network.open()

    let first = Task { try await network.changes().first { _ in true } }
    var waits = clock.requested.makeAsyncIterator()

    #expect(await waits.next() == .seconds(9))

    first.cancel()
    _ = try? await first.value

  }

  // MARK: - Unreachable

  @Test func failsToOpenWhenTheUnitDoesNotAnswer() async {

    let http = RoutedHTTPClient()

    await #expect(throws: HubProError.unexpectedStatus(404)) { try await network(http).open() }

  }

}

/// A clock that never moves: it says how long each sleep was asked for, and waits to be canceled.
final class IntervalClock: Clock, Sendable {

  typealias Instant = ContinuousClock.Instant

  private let start = ContinuousClock.now
  let requested: AsyncStream<Duration>
  private let continuation: AsyncStream<Duration>.Continuation
  private let never: AsyncStream<Void>

  init() {

    (requested, continuation) = AsyncStream.makeStream()
    never = AsyncStream { _ in }

  }

  var now: Instant { start }

  var minimumResolution: Duration { .zero }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {

    continuation.yield(start.duration(to: deadline))

    for await _ in never {}

    throw CancellationError()

  }

}
