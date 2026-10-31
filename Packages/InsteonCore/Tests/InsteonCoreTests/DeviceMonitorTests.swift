import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// A made-up leak sensor, whose model and identity no real product has.
enum MonitorExample {

  static let sensor = InsteonAddress(0x5C, 0x6D, 0x01)

  static let stranger = InsteonAddress(0x5C, 0x6D, 0x02)

  static let modem = InsteonAddress(0x11, 0x22, 0x33)

  static let sensorIdentity = ReportedIdentity(category: 0x10, subcategory: 0x7A, firmwareVersion: 0x45)

  static let sensorProfile = DeviceProfile(
    model: "9201",
    name: "Example Leak Sensor",
    identities: [DeviceIdentity(category: 0x10, subcategory: 0x7A)],
    groups: [
      DeviceProfile.Group(number: 1, name: "Dry", role: .controller),
      DeviceProfile.Group(number: 2, name: "Wet", role: .controller),
      DeviceProfile.Group(number: 4, name: "Heartbeat", role: .controller)
    ],
    capabilities: [
      .groupEvents([
        DeviceCapability.GroupEvent(group: 1, command1: 0x11, event: "dry"),
        DeviceCapability.GroupEvent(group: 2, command1: 0x11, event: "wet")
      ]),
      .heartbeat(group: 4, interval: .seconds(3_600))
    ]
  )

  static let catalog = DeviceCatalog(profiles: [sensorProfile])

  /// A device's ALL-Link broadcast to a group.
  static func broadcast(from device: InsteonAddress, group: UInt8, command1: UInt8) -> ModemReply {

    .messageReceived(ReceivedMessage(
      sender: device,
      destination: InsteonAddress(0x00, 0x00, group),
      flags: MessageFlags(messageType: .allLinkBroadcast),
      command: Command(command1: command1, command2: 0x00)
    ))

  }

  /// A device's ALL-Link cleanup of a group, sent to the modem.
  static func cleanup(from device: InsteonAddress, group: UInt8, command1: UInt8) -> ModemReply {

    .messageReceived(ReceivedMessage(
      sender: device,
      destination: modem,
      flags: MessageFlags(messageType: .allLinkCleanup),
      command: Command(command1: command1, command2: group)
    ))

  }

  /// The sensor's SET Button Pressed broadcast, as a responder.
  static let setButtonPressed = ReceivedMessage(
    sender: sensor,
    destination: InsteonAddress(0x10, 0x7A, 0x45),
    flags: MessageFlags(messageType: .broadcast),
    command: Command(command1: 0x01, command2: 0x00)
  )

  /// A device's acknowledgment of Light On.
  static func acknowledgment(from device: InsteonAddress) -> ReceivedMessage {

    ReceivedMessage(
      sender: device,
      destination: modem,
      flags: MessageFlags(messageType: .directAcknowledgment),
      command: Command(command1: 0x11, command2: 0xFF)
    )

  }

}

/// A modem whose replies a test sends, one at a time; it answers no requests.
actor MonitorModem: LinkingModem {

  private var subscribers: [Int: AsyncStream<ModemReply>.Continuation] = [:]

  private var nextSubscriber: Int = 0

  /// The modem hears a reply, and passes it to every stream reading its replies.
  func receive(_ reply: ModemReply) {

    for subscriber in subscribers.values {

      subscriber.yield(reply)

    }

  }

  /// The modem's connection closes, so every stream of its replies finishes.
  func close() {

    for subscriber in subscribers.values {

      subscriber.finish()

    }

    subscribers = [:]

  }

  func send(_ command: SerialCommand) async throws {

    throw ModemError.connectionClosed

  }

  func modemInfo() async throws -> ModemInfo {

    throw ModemError.connectionClosed

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    throw ModemError.connectionClosed

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    throw ModemError.connectionClosed

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    throw ModemError.connectionClosed

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    throw ModemError.connectionClosed

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    []

  }

  func allLinkRecords() async throws -> [AllLinkRecord] {

    []

  }

  func replies() -> AsyncStream<ModemReply> {

    let (stream, continuation): (AsyncStream<ModemReply>, AsyncStream<ModemReply>.Continuation) = AsyncStream<ModemReply>.makeStream()
    let id: Int = nextSubscriber

    nextSubscriber += 1
    subscribers[id] = continuation

    continuation.onTermination = { [weak self] (_: AsyncStream<ModemReply>.Continuation.Termination) -> Void in

      guard let self else {

        return

      }

      Task {

        await self.removeSubscriber(id)

      }

    }

    return stream

  }

  private func removeSubscriber(_ id: Int) {

    subscribers[id] = nil

  }

}

/// ``DeviceMonitor`` on a scripted modem, a ``TestClock`` that never moves, so repeats fall in
/// the catalog's windows, and fixed times.
struct DeviceMonitorTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  /// A network on the modem, whose registry knows the devices given.
  func network(_ modem: MonitorModem, knowing identities: [InsteonAddress: ReportedIdentity] = [:]) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: MonitorExample.catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)),
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  @Test(.timeLimit(.minutes(1))) func readsAKnownDevicesGroupCommandAsItsEventOnce() async throws {

    let modem = MonitorModem()
    let network: DeviceNetwork = network(modem, knowing: [MonitorExample.sensor: MonitorExample.sensorIdentity])
    var changes = await network.monitor.changes().makeAsyncIterator()

    await modem.receive(MonitorExample.broadcast(from: MonitorExample.sensor, group: 2, command1: 0x11))
    await modem.receive(MonitorExample.cleanup(from: MonitorExample.sensor, group: 2, command1: 0x11))
    await modem.receive(.messageReceived(MonitorExample.acknowledgment(from: MonitorExample.sensor)))

    let wet: DeviceMonitorEvent? = await changes.next()
    // The cleanup repeats the broadcast, so the acknowledgment comes next.
    let acknowledgment: DeviceMonitorEvent? = await changes.next()

    #expect(wet == .groupCommand(DeviceGroupCommand(
      device: MonitorExample.sensor,
      group: 2,
      command1: 0x11,
      commandName: "Light On",
      event: "wet",
      isOn: true,
      productName: "Example Leak Sensor 9201"
    )))
    #expect(acknowledgment == .message(DeviceMessageSummary(MonitorExample.acknowledgment(from: MonitorExample.sensor))))
    #expect(await network.state(of: MonitorExample.sensor)?.lastSeen != nil)

  }

  @Test(.timeLimit(.minutes(1))) func readsAHeartbeatToTheProfilesHeartbeatGroup() async throws {

    let modem = MonitorModem()
    let network: DeviceNetwork = network(modem, knowing: [MonitorExample.sensor: MonitorExample.sensorIdentity])
    var changes = await network.monitor.changes().makeAsyncIterator()

    await modem.receive(MonitorExample.broadcast(from: MonitorExample.sensor, group: 4, command1: 0x13))

    let heartbeat: DeviceMonitorEvent? = await changes.next()

    #expect(heartbeat == .heartbeat(MonitorExample.sensor, group: 4))

  }

  @Test(.timeLimit(.minutes(1))) func learnsAnIdentityFromTheSETButtonAndRecordsIt() async throws {

    let modem = MonitorModem()
    let network: DeviceNetwork = network(modem)
    var changes = await network.monitor.changes().makeAsyncIterator()

    await modem.receive(.messageReceived(MonitorExample.setButtonPressed))
    await modem.receive(.messageReceived(MonitorExample.setButtonPressed))
    await modem.receive(MonitorExample.broadcast(from: MonitorExample.sensor, group: 1, command1: 0x11))

    let pressed: DeviceMonitorEvent? = await changes.next()
    // The repeat of the broadcast isn't reported, and the device is known from then on.
    let dry: DeviceMonitorEvent? = await changes.next()

    guard case let .setButtonPressed(press)? = pressed, case let .groupCommand(command)? = dry else {

      Issue.record("Expected a SET button press and a group command, got \(String(describing: pressed)) and \(String(describing: dry)).")

      return

    }

    #expect(press.device == MonitorExample.sensor)
    #expect(press.identity == MonitorExample.sensorIdentity)
    #expect(press.command1 == 0x01)
    #expect(press.role == "responder")
    #expect(press.productName == "Example Leak Sensor 9201")
    #expect(command.event == "dry")
    #expect(await network.registry.device(MonitorExample.sensor)?.identity == MonitorExample.sensorIdentity)
    #expect(await network.snapshot().registry.identities[MonitorExample.sensor] == MonitorExample.sensorIdentity)

  }

  @Test(.timeLimit(.minutes(1))) func readsAnUnknownDevicesGroupCommandWithoutAnEvent() async throws {

    let modem = MonitorModem()
    let network: DeviceNetwork = network(modem)
    var changes = await network.monitor.changes().makeAsyncIterator()

    await modem.receive(MonitorExample.broadcast(from: MonitorExample.stranger, group: 1, command1: 0x13))

    let command: DeviceMonitorEvent? = await changes.next()

    #expect(command == .groupCommand(DeviceGroupCommand(
      device: MonitorExample.stranger,
      group: 1,
      command1: 0x13,
      commandName: "Light Off",
      event: nil,
      isOn: false,
      productName: nil
    )))
    #expect(await network.registry.device(MonitorExample.stranger) == nil)

  }

  @Test(.timeLimit(.minutes(1))) func addsRawBytesAndRepliesWhenAsked() async throws {

    let modem = MonitorModem()
    let network: DeviceNetwork = network(modem)
    let acknowledgment: ReceivedMessage = MonitorExample.acknowledgment(from: MonitorExample.stranger)
    var changes = await network.monitor.changes(includingRaw: true).makeAsyncIterator()

    await modem.receive(.messageReceived(acknowledgment))
    await modem.receive(.userReset)
    await modem.receive(.negativeAcknowledgment)
    await modem.receive(.messageReceived(MonitorExample.setButtonPressed))
    await modem.receive(.messageReceived(MonitorExample.setButtonPressed))

    var events: [DeviceMonitorEvent] = []

    for _ in 0..<6 {

      if let event: DeviceMonitorEvent = await changes.next() {

        events.append(event)

      }

    }

    guard events.count == 6, case .setButtonPressed = events[5] else {

      Issue.record("Expected six events ending with a SET button press, got \(events).")

      return

    }

    #expect(events[0] == .rawMessage(acknowledgment.modemFrame))
    #expect(events[1] == .message(DeviceMessageSummary(acknowledgment)))
    #expect(events[2] == .modem(.userReset))
    #expect(events[3] == .rawReply(kind: "NAK"))
    #expect(events[4] == .rawMessage(MonitorExample.setButtonPressed.modemFrame))

    // The repeat is reported only by its bytes, not as a message.
    await modem.receive(.messageReceived(acknowledgment))

    let repeated: DeviceMonitorEvent? = await changes.next()
    let next: DeviceMonitorEvent? = await changes.next()

    #expect(repeated == .rawMessage(MonitorExample.setButtonPressed.modemFrame))
    #expect(next == .rawMessage(acknowledgment.modemFrame))

  }

  @Test func readsTheModemsOwnReports() {

    let link = AllLinkingCompleted(linkCode: 0x01, group: 3, address: MonitorExample.sensor, category: nil, subcategory: nil, firmwareVersion: nil)

    #expect(ModemNotice(.allLinkingCompleted(link)) == .allLinkingCompleted(MonitorExample.sensor, group: 3, modemRole: link.mode?.name))
    #expect(ModemNotice(.allLinkCleanupFailed(group: 5, address: MonitorExample.sensor)) == .allLinkCleanupFailed(MonitorExample.sensor, group: 5))
    #expect(ModemNotice(.userReset) == .userReset)
    #expect(ModemNotice(.negativeAcknowledgment) == nil)
    #expect(DeviceMonitor.replyKind(.negativeAcknowledgment) == "NAK")

  }

  @Test(.timeLimit(.minutes(1))) func endsTheStreamWhenTheReadersTaskIsCanceled() async throws {

    let modem = MonitorModem()
    let network: DeviceNetwork = network(modem)
    let changes: AsyncStream<DeviceMonitorEvent> = await network.monitor.changes()

    let reader = Task { () -> Int in

      var count: Int = 0

      for await _ in changes {

        count += 1

      }

      return count

    }

    reader.cancel()

    // The reader finishes, rather than waiting for the modem, however far it got first.
    #expect(await reader.value == 0)

  }

  @Test(.timeLimit(.minutes(1))) func endsTheStreamWhenTheModemsRepliesFinish() async throws {

    let modem = MonitorModem()
    let network: DeviceNetwork = network(modem, knowing: [MonitorExample.sensor: MonitorExample.sensorIdentity])
    let changes: AsyncStream<DeviceMonitorEvent> = await network.monitor.changes()

    await modem.receive(MonitorExample.broadcast(from: MonitorExample.sensor, group: 2, command1: 0x11))
    await modem.close()

    var events: [DeviceMonitorEvent] = []

    for await event in changes {

      events.append(event)

    }

    #expect(events.count == 1)

  }

}
