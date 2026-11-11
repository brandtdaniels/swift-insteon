import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// What each message a ``Device`` sends needs granted, from the effect its command set gives
/// the message's bytes and the effect the flow that builds it declares, on an in-memory modem.
/// No name, product or flag here is a real one's.
struct SendAuthorizationTests {

  let clock: TestClock = TestClock()

  static let described = InsteonAddress(0x3A, 0x4B, 0x41)

  static let describedIdentity = ReportedIdentity(category: 0x01, subcategory: 0x76, firmwareVersion: 0x45)

  /// A dimmer the catalog doesn't know, so its category gives the commands.
  static let categoryOnly = InsteonAddress(0x3A, 0x4B, 0x42)

  static let categoryOnlyIdentity = ReportedIdentity(category: 0x01, subcategory: 0x55, firmwareVersion: 0x45)

  /// The made-up catalog's entries, each with the effect fields the test gives.
  static func json(lightOn: String = #""effect": "actuation", "idempotent": true"#, readStatus: String = #""effect": "readOnly", "idempotent": true"#, ping: String? = nil) -> String {

    let pingEntry: String = ping.map { (fields: String) -> String in

      #", { "name": "ping", "description": "Answers.", "command1": "0x0F", "command2": "0x00", \#(fields) }"#

    } ?? ""

    return #"""
      {
        "devices": [{
          "model": "9501",
          "name": "Example Effects Relay",
          "identities": [{ "category": "0x01", "subcategory": "0x76" }],
          "commandSets": [{ "commandSet": "exampleEffects", "category": "0x01", "subcategory": "0x76" }],
          "groups": [{ "number": "0x01", "name": "Load", "role": "both", "type": "load" }],
          "capabilities": [],
          "sources": ["A"]
        }],
        "commandSets": [{
          "id": "exampleEffects",
          "name": "Example effects relay",
          "description": "Commands that each do something different.",
          "standardCommands": [
            { "name": "lightOn", "description": "On.", "command1": "0x11", "command2": "0xFF", \#(lightOn) },
            { "name": "lightOff", "description": "Off.", "command1": "0x13", "command2": "0x00", "effect": "actuation", "idempotent": true },
            { "name": "readStatus", "description": "Reads the state.", "command1": "0x19", "command2": "0x00", \#(readStatus) },
            { "name": "tune", "description": "Stores a setting.", "command1": "0x56", "command2": "0x00", "effect": "configuration", "idempotent": true },
            { "name": "wipe", "description": "Erases what the device keeps.", "command1": "0x55", "command2": "0x00", "effect": "destructive", "idempotent": false },
            { "name": "erase", "description": "Never sent.", "command1": "0x20", "command2": "0x0A", "guard": "never", "effect": "destructive", "idempotent": false },
            { "name": "unmarked", "description": "Says nothing of its effect.", "command1": "0x58", "command2": "0x00" },
            { "name": "oddity", "description": "An effect this package doesn't know.", "command1": "0x59", "command2": "0x00", "effect": "sideEffect", "idempotent": true },
            { "name": "chimeOn", "description": "Never sent.", "command1": "0x45", "command2": "0x01", "guard": "never", "effect": "destructive", "idempotent": false }
            \#(pingEntry)
          ],
          "extendedCommands": [
            { "name": "resetAll", "description": "Restores factory settings.", "command1": "0x36", "command2": "0x00", "fixed": [{ "position": 1, "value": "0x01" }], "effect": "destructive", "idempotent": false },
            { "name": "writeMode", "description": "Overwrites a stored mode.", "command1": "0x2E", "command2": "0x00", "fixed": [{ "position": 2, "value": "0x07" }], "effect": "destructive", "idempotent": false },
            { "name": "readMode", "description": "Reads the stored mode.", "command1": "0x2E", "command2": "0x00", "fixed": [{ "position": 2, "value": "0x00" }], "effect": "readOnly", "idempotent": true }
          ],
          "groupTypes": [{
            "name": "load",
            "label": "Load",
            "kind": "relay",
            "state": { "command": "readStatus" },
            "actions": [
              { "name": "on", "label": "On", "command": "lightOn" },
              { "name": "off", "label": "Off", "command": "lightOff" }
            ]
          }],
          "sources": ["A"]
        }]
      }
      """#

  }

  /// The messages the modem was asked to send, in order.
  actor Sent {

    private(set) var standard: [Command] = []

    private(set) var extended: [Command] = []

    func record(_ operation: InMemoryModem.Operation) {

      switch operation {
      case let .standardRequest(message):
        standard.append(message.command)
      case let .extendedRequest(message):
        extended.append(message.command)
      default:
        break
      }

    }

  }

  func network(json: String = Self.json()) async throws -> (DeviceNetwork, Sent) {

    let modem = InMemoryModem()
    let sent = Sent()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      await sent.record(operation)

    }

    let network = DeviceNetwork(
      modem: modem,
      catalog: try DeviceCatalog(json: Data(json.utf8)),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [Self.described: Self.describedIdentity, Self.categoryOnly: Self.categoryOnlyIdentity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    return (network, sent)

  }

  func message(_ command1: UInt8, _ command2: UInt8 = 0x00, to device: InsteonAddress = Self.described) -> DirectMessage {

    DirectMessage(to: device, command1: command1, command2: command2, data: nil, hasChecksum: false)

  }

  // MARK: - Operations that name the act

  @Test(.timeLimit(.minutes(1))) func turnsOnWithAnActuationEntry() async throws {

    let (network, sent) = try await network()

    _ = try await network.device(Self.described).turnOn()

    #expect(await sent.standard == [Command(command1: 0x11, command2: 0xFF)])

  }

  @Test(.timeLimit(.minutes(1))) func readsStatusWithAReadOnlyEntry() async throws {

    let (network, sent) = try await network()

    _ = try await network.device(Self.described).status()

    #expect(await sent.standard.contains(Command(command1: 0x19, command2: 0x00)))

  }

  @Test(.timeLimit(.minutes(1))) func asksForConsentWhenTheEntryOfAReadIsConfiguration() async throws {

    let (network, sent) = try await network(json: Self.json(readStatus: #""effect": "configuration", "idempotent": true"#))

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      _ = try await network.device(Self.described).status()

    }

    guard case let .needsConsent(.status, effect, _)? = error else {

      Issue.record("Expected needsConsent, got \(String(describing: error)).")

      return

    }

    #expect(effect == .configuration)
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func readsAnActionWhoseEntryDiffersFromWhatItsFlowDeclaresAsDestructive() async throws {

    // The catalog says configuration and the flow declares actuation: neither stands for the
    // other, so the stricter of the two is destructive.
    let (network, sent) = try await network(json: Self.json(lightOn: #""effect": "configuration", "idempotent": true"#))

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      _ = try await network.device(Self.described).turnOn()

    }

    guard case let .needsConsent(.turnOn, effect, _)? = error else {

      Issue.record("Expected needsConsent, got \(String(describing: error)).")

      return

    }

    #expect(effect == .destructive)
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func asksForConsentWhenTheEntryOfAnActionIsDestructive() async throws {

    let (network, sent) = try await network(json: Self.json(lightOn: #""effect": "destructive", "idempotent": false"#))

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      _ = try await network.device(Self.described).turnOn()

    }

    guard case let .needsConsent(.turnOn, effect, _)? = error else {

      Issue.record("Expected needsConsent, got \(String(describing: error)).")

      return

    }

    #expect(effect == .destructive)
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func treatsAnEntryWithNoEffectAsDestructive() async throws {

    let (network, sent) = try await network(json: Self.json(lightOn: #""idempotent": true"#))

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      _ = try await network.device(Self.described).turnOn()

    }

    guard case let .needsConsent(.turnOn, effect, _)? = error else {

      Issue.record("Expected needsConsent, got \(String(describing: error)).")

      return

    }

    #expect(effect == .destructive)
    #expect(await sent.standard.isEmpty)

  }

  // MARK: - Messages a flow builds

  @Test(.timeLimit(.minutes(1))) func pingsADeviceWithNoCommandSetBecauseThePingDeclaresItsEffect() async throws {

    let (network, sent) = try await network()

    try await network.device(Self.categoryOnly).ping()

    #expect(await sent.standard == [StandardDirectCommand.ping.command])

  }

  @Test(.timeLimit(.minutes(1))) func turnsOnADeviceWithNoCommandSetBecauseTheCategoryFallbackDeclaresActuation() async throws {

    let (network, sent) = try await network()

    _ = try await network.device(Self.categoryOnly).turnOn()

    #expect(await sent.standard == [Command(command1: 0x11, command2: 0xFF)])

  }

  @Test(.timeLimit(.minutes(1))) func usesTheStricterOfTheCatalogsEffectAndTheEffectAFlowDeclares() async throws {

    // The command set marks the bytes of Ping as actuation; the flow declares read only, and
    // the operation that sends it grants only reading.
    let (network, sent) = try await network(json: Self.json(ping: #""effect": "actuation", "idempotent": true"#))

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      try await network.device(Self.described).ping()

    }

    guard case let .needsConsent(.status, effect, _)? = error else {

      Issue.record("Expected needsConsent, got \(String(describing: error)).")

      return

    }

    #expect(effect == .actuation)
    #expect(await sent.standard.isEmpty)

  }

  // MARK: - A message sent as given

  func extended(_ command1: UInt8, _ command2: UInt8, _ data: [UInt8], hasChecksum: Bool = true) -> DirectMessage {

    DirectMessage(to: Self.described, command1: command1, command2: command2, data: data, hasChecksum: hasChecksum)

  }

  @Test(.timeLimit(.minutes(1))) func asksForConsentToSendAnExtendedDestructiveWriteThatCarriesTheDefaultChecksum() async throws {

    let (network, sent) = try await network()

    // The entry has no integrity check, and the default checksum sits in D14.
    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(extended(0x2E, 0x00, [0x00, 0x07, 0x05]), collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration, .link, .actuation], allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .needsConsent(.destructive))
    #expect(await sent.extended.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func asksForConsentToSendAFactoryResetWithPaddingAfterItsFixedBytes() async throws {

    let (network, sent) = try await network()

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(extended(0x36, 0x00, [0x01, 0x00, 0x00, 0x00, 0x09]), collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration, .link, .actuation], allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .needsConsent(.destructive))
    #expect(await sent.extended.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func asksForConsentToSendAStandardDestructiveCommandAsAnExtendedMessage() async throws {

    let (network, sent) = try await network()

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(extended(0x55, 0x00, [0x55, 0x00]), collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration, .link, .actuation], allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .needsConsent(.destructive))
    #expect(await sent.extended.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func sendsAnExtendedDestructiveWriteWhenTheConsentGrantsIt() async throws {

    let (network, sent) = try await network()

    _ = try await network.send(extended(0x2E, 0x00, [0x00, 0x07, 0x05]), collectingFor: .seconds(0), consent: SendConsent(effects: [.destructive])) { (_: ReceivedFrame) -> Void in }

    #expect(await sent.extended == [Command(command1: 0x2E, command2: 0x00)])

  }

  @Test(.timeLimit(.minutes(1))) func keepsAReadWithExtraBytesReadOnlyWhenItMatchesOnlyAReadOnlyEntry() async throws {

    let (network, sent) = try await network()

    _ = try await network.send(extended(0x2E, 0x00, [0x01, 0x00, 0x00]), collectingFor: .seconds(0)) { (_: ReceivedFrame) -> Void in }

    #expect(await sent.extended == [Command(command1: 0x2E, command2: 0x00)])

  }

  @Test(.timeLimit(.minutes(1))) func refusesAnEntryTheCatalogNeverSendsWhateverItsCmd1() async throws {

    let (network, sent) = try await network()

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(message(0x45, 0x01), collectingFor: .seconds(0), consent: .everything) { (_: ReceivedFrame) -> Void in }

    }

    guard case .neverSentToDevice? = error else {

      Issue.record("Expected a refusal, got \(String(describing: error)).")

      return

    }

    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func sendsAReadOnlyMessageAsGivenWithNoConsent() async throws {

    let (network, sent) = try await network()

    _ = try await network.send(message(0x19), collectingFor: .seconds(0)) { (_: ReceivedFrame) -> Void in }

    #expect(await sent.standard == [Command(command1: 0x19, command2: 0x00)])

  }

  @Test(.timeLimit(.minutes(1))) func asksForConsentToSendADestructiveMessageAsGiven() async throws {

    let (network, sent) = try await network()

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(message(0x55), collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration, .link, .actuation], allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .needsConsent(.destructive))
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func sendsADestructiveMessageAsGivenWhenTheConsentGrantsIt() async throws {

    let (network, sent) = try await network()

    _ = try await network.send(message(0x55), collectingFor: .seconds(0), consent: SendConsent(effects: [.destructive])) { (_: ReceivedFrame) -> Void in }

    #expect(await sent.standard == [Command(command1: 0x55, command2: 0x00)])

  }

  @Test(.timeLimit(.minutes(1))) func refusesAMessageTheCatalogNeverSendsWhateverTheConsentGrants() async throws {

    let (network, sent) = try await network()

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(message(0x20, 0x0A), collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration, .link, .actuation, .destructive], allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    }

    guard case .neverSentToDevice? = error else {

      Issue.record("Expected a refusal, got \(String(describing: error)).")

      return

    }

    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func refusesPokeWhateverTheConsentGrants() async throws {

    let (network, sent) = try await network()

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(message(0x29), collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration, .link, .actuation, .destructive], allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .protected(ProtectedCommand(Command(command1: 0x29, command2: 0x00))!))
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func asksForConsentToSendAMessageNoEntryDescribes() async throws {

    let (network, sent) = try await network()

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(message(0x60), collectingFor: .seconds(0), consent: SendConsent(effects: [.configuration, .link, .actuation])) { (_: ReceivedFrame) -> Void in }

    }

    #expect(error == .needsConsent(nil))
    #expect(await sent.standard.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func sendsAMessageNoEntryDescribesWhenTheConsentAllowsIt() async throws {

    let (network, sent) = try await network()

    _ = try await network.send(message(0x60), collectingFor: .seconds(0), consent: SendConsent(allowsUndescribed: true)) { (_: ReceivedFrame) -> Void in }

    #expect(await sent.standard == [Command(command1: 0x60, command2: 0x00)])

  }

  @Test(.timeLimit(.minutes(1))) func readsAnEntryWithNoEffectOrAnUnknownOneAsDestructive() async throws {

    let (network, sent) = try await network()
    let everythingButDestructive = SendConsent(effects: [.configuration, .link, .actuation], allowsUndescribed: true)

    for command1: UInt8 in [0x58, 0x59] {

      let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

        _ = try await network.send(message(command1), collectingFor: .seconds(0), consent: everythingButDestructive) { (_: ReceivedFrame) -> Void in }

      }

      #expect(error == .needsConsent(.destructive))

    }

    #expect(await sent.standard.isEmpty)

  }

}

extension SendConsent {

  /// A consent that grants every effect and the undescribed, for tests of what the floor and
  /// the guards refuse whatever is granted.
  static let everything = SendConsent(effects: [.configuration, .link, .actuation, .destructive], allowsUndescribed: true)

}
