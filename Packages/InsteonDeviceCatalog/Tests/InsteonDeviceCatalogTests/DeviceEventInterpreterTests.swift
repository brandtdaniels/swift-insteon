import Testing
import InsteonDeviceCatalog
import InsteonProtocol

struct DeviceEventInterpreterTests {

  let sensor = InsteonAddress(0x2A, 0x3B, 0x4C)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  let start = ContinuousClock.now

  func interpreter() throws -> DeviceEventInterpreter<ContinuousClock.Instant> {

    DeviceEventInterpreter(catalog: try DeviceCatalog(json: DeviceCatalogTests.json(DeviceCatalogTests.leakSensor)))

  }

  /// A broadcast whose To address carries an identity, such as a SET Button Pressed.
  func identity(command1: UInt8, category: UInt8 = 0x10, subcategory: UInt8 = 0x08, command2: UInt8 = 0x00) -> ReceivedMessage {

    ReceivedMessage(
      sender: sensor,
      destination: InsteonAddress(category, subcategory, 0x41),
      flags: MessageFlags(messageType: .broadcast),
      command: Command(command1: command1, command2: command2)
    )

  }

  func groupBroadcast(group: UInt8, command1: UInt8) -> ReceivedMessage {

    ReceivedMessage(
      sender: sensor,
      destination: InsteonAddress(0x00, 0x00, group),
      flags: MessageFlags(messageType: .allLinkBroadcast),
      command: Command(command1: command1, command2: 0x00)
    )

  }

  @Test func learnsAProfileFromTheSetButton() throws {

    var interpreter = try interpreter()

    let events = interpreter.events(from: identity(command1: 0x02), at: start)

    let profile = try #require(interpreter.profile(of: sensor))
    #expect(profile.model == "2852")
    #expect(events == [.identified(sensor, profile: profile)])

  }

  @Test func namesWhatAKnownDevicesGroupCommandMeans() throws {

    var interpreter = try interpreter()
    _ = interpreter.events(from: identity(command1: 0x02), at: start)

    let events = interpreter.events(from: groupBroadcast(group: 0x02, command1: 0x11), at: start)

    #expect(events == [.groupCommand(GroupCommand(controller: sensor, group: 0x02, command1: 0x11, command2: 0x00, source: .broadcast), event: "wet")])

  }

  @Test func reportsACommandOnce() throws {

    var interpreter = try interpreter()
    _ = interpreter.events(from: identity(command1: 0x02), at: start)
    _ = interpreter.events(from: groupBroadcast(group: 0x02, command1: 0x11), at: start)

    // Sensors send each broadcast twice.
    #expect(interpreter.events(from: groupBroadcast(group: 0x02, command1: 0x11), at: start + .milliseconds(300)).isEmpty)

  }

  @Test func readsTheHeartbeatGroupAsAHeartbeatWithItsCommand() throws {

    var interpreter = try interpreter()
    _ = interpreter.events(from: identity(command1: 0x02), at: start)

    // The leak sensor's heartbeat is off when it's wet.
    #expect(interpreter.events(from: groupBroadcast(group: 0x04, command1: 0x13), at: start)
      == [.heartbeat(GroupCommand(controller: sensor, group: 0x04, command1: 0x13, command2: 0x00, source: .broadcast))])

  }

  @Test func readsAHeartbeatBroadcastWithItsBatteryLevel() throws {

    var interpreter = try interpreter()
    let expected = try #require(interpreter.catalog.profile(model: "2852"))

    let events = interpreter.events(from: identity(command1: 0x04, command2: 0x80), at: start)

    #expect(events == [
      .identified(sensor, profile: expected),
      .heartbeatBroadcast(Heartbeat(sender: sensor, batteryLevel: 0x80, category: 0x10, subcategory: 0x08, firmwareVersion: 0x41)),
    ])

  }

  @Test func reportsARepeatedIdentityBroadcastOnce() throws {

    var interpreter = try interpreter()
    _ = interpreter.events(from: identity(command1: 0x27), at: start)

    #expect(interpreter.events(from: identity(command1: 0x27), at: start + .milliseconds(300)).isEmpty)
    #expect(interpreter.events(from: identity(command1: 0x27), at: start + .seconds(2)).last == .statusChanged(sensor))

  }

  @Test func readsAStatusChange() throws {

    var interpreter = try interpreter()

    let events = interpreter.events(from: identity(command1: 0x27), at: start)

    #expect(events.last == .statusChanged(sensor))

  }

  @Test func passesOnAnUnknownDevicesCommandWithoutAMeaning() throws {

    var interpreter = try interpreter()

    let events = interpreter.events(from: groupBroadcast(group: 0x01, command1: 0x11), at: start)

    #expect(events == [.groupCommand(GroupCommand(controller: sensor, group: 0x01, command1: 0x11, command2: 0x00, source: .broadcast), event: nil)])

  }

  // A heartbeat from a device the catalog doesn't know mustn't undo what the app remembered.
  @Test func keepsAProfileWhenTheIdentityIsUnknown() throws {

    var interpreter = try interpreter()
    let profile = try #require(interpreter.catalog.profile(model: "2852"))
    interpreter.remember(profile, for: sensor)

    let events = interpreter.events(from: identity(command1: 0x04, category: 0x01, subcategory: 0x20), at: start)

    #expect(events.first == .identified(sensor, profile: nil))
    #expect(interpreter.profile(of: sensor) == profile)

  }

  @Test func findsProfilesAgainInANewCatalog() throws {

    var interpreter = try interpreter()
    _ = interpreter.events(from: identity(command1: 0x02, category: 0x01, subcategory: 0x20), at: start)
    #expect(interpreter.profile(of: sensor) == nil)

    let dimmer = #"{ "model": "2477D", "name": "SwitchLinc Dimmer", "identities": [{ "category": "0x01", "subcategory": "0x20" }], "capabilities": [{ "kind": "dimmable" }], "sources": ["A"] }"#
    interpreter.catalog = try DeviceCatalog(json: DeviceCatalogTests.json(dimmer))

    #expect(interpreter.profile(of: sensor)?.model == "2477D")

  }

  @Test func usesARememberedProfile() throws {

    var interpreter = try interpreter()
    let profile = try #require(interpreter.catalog.profile(model: "2852"))
    interpreter.remember(profile, for: sensor)

    #expect(interpreter.events(from: groupBroadcast(group: 0x01, command1: 0x11), at: start).first == .groupCommand(
      GroupCommand(controller: sensor, group: 0x01, command1: 0x11, command2: 0x00, source: .broadcast),
      event: "dry"
    ))

    interpreter.remember(nil, for: sensor)
    #expect(interpreter.profile(of: sensor) == nil)

  }

  @Test func ignoresADirectMessage() throws {

    var interpreter = try interpreter()
    let direct = ReceivedMessage(sender: sensor, destination: modem, flags: .direct, command: Command(command1: 0x11))

    #expect(interpreter.events(from: direct, at: start).isEmpty)

  }

}
