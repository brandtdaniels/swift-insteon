import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// The byte floor under every guard: the four protected Set Operating Flags, `0x0C`, `0x0E`,
/// `0x19` and `0x00`, which cut most devices off from the modem or lock them, and
/// Poke (cmd1 `0x29`), pushed through every send path. Each is refused with nothing written,
/// for a device the catalog doesn't know, with no catalog at all, and for a command set that
/// doesn't name the cmd2; bytes the floor doesn't hold still go through, and so does a cmd2 a
/// command set names for a flag it doesn't guard.
struct GuardedBytesTests {

  let clock: TestClock = TestClock()

  /// The device every message is for.
  static let address = InsteonAddress(0x3A, 0x4B, 0x41)

  /// Every protected command's bytes, with a cmd2 for Poke One Byte.
  static let protectedCommands: [Command] = [
    Command(command1: 0x20, command2: 0x0C),
    Command(command1: 0x20, command2: 0x0E),
    Command(command1: 0x20, command2: 0x19),
    Command(command1: 0x20, command2: 0x00),
    Command(command1: 0x29, command2: 0xAA)
  ]

  /// Bytes the floor doesn't hold: Set Operating Flags radio on, Set Address MSB, which writes
  /// nothing, and Light On.
  static let allowedCommands: [Command] = [
    Command(command1: 0x20, command2: 0x0D),
    Command(command1: 0x28, command2: 0x0F),
    Command(command1: 0x11, command2: 0xFF)
  ]

  /// What the network knows about the device.
  enum Knowledge: String, CaseIterable, Sendable {

    /// The bundled catalog, which doesn't know the device's identity, and a registry that
    /// doesn't know the device.
    case unknownDevice

    /// No catalog, and a registry that knows the device's identity.
    case noCatalog

    /// A command set with no operating flags, so none that names a protected cmd2, that fills
    /// Set Operating Flags' cmd2 with the caller's value.
    case noProgrammingLockFlag

  }

  /// A command set with no operating flags at all: its off action fills Set Operating Flags'
  /// cmd2 with the off value, the protected `0x00`, and it lists Poke One Byte.
  static let flaglessJSON = #"""
    {
      "devices": [{
        "model": "9501",
        "name": "Example Flagless Switch",
        "identities": [{ "category": "0x02", "subcategory": "0x7B" }],
        "commandSets": [{ "commandSet": "exampleFlagless", "category": "0x02", "subcategory": "0x7B" }],
        "groups": [{ "number": "0x01", "name": "Load", "role": "both", "type": "load" }],
        "capabilities": [],
        "sources": ["A"]
      }],
      "commandSets": [{
        "id": "exampleFlagless",
        "name": "Example flagless switch",
        "description": "A command set with no operating flags.",
        "standardCommands": [
          { "name": "lightOn", "description": "On.", "command1": "0x11", "command2": "0xFF" },
          { "name": "setFlags", "description": "Set Operating Flags with a cmd2 the caller gives.", "command1": "0x20",
            "parameter": { "name": "flags", "description": "The cmd2." } },
          { "name": "poke", "description": "Poke One Byte.", "command1": "0x29",
            "parameter": { "name": "byte", "description": "The byte." } }
        ],
        "groupTypes": [{
          "name": "load",
          "label": "Load",
          "kind": "relay",
          "actions": [
            { "name": "on", "label": "On", "command": "lightOn" },
            { "name": "off", "label": "Off", "command": "setFlags" }
          ]
        }],
        "sources": ["A"]
      }]
    }
    """#

  /// The identity the flagless command set's device reports.
  static let flaglessIdentity = ReportedIdentity(category: 0x02, subcategory: 0x7B, firmwareVersion: 0x41)

  /// A network on `modem` that knows the device as `knowledge` says.
  func network(_ modem: SettingsModem, knowing knowledge: Knowledge) throws -> DeviceNetwork {

    let catalog: DeviceCatalog?
    let identities: [InsteonAddress: ReportedIdentity]

    switch knowledge {
    case .unknownDevice:
      catalog = try DeviceCatalog.bundled()
      identities = [:]
    case .noCatalog:
      catalog = nil
      identities = [Self.address: Self.flaglessIdentity]
    case .noProgrammingLockFlag:
      catalog = try DeviceCatalog(json: Data(Self.flaglessJSON.utf8))
      identities = [Self.address: Self.flaglessIdentity]
    }

    return DeviceNetwork(
      modem: modem,
      catalog: catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

  }

  /// A modem whose device has its flags clear.
  static func modem() -> SettingsModem {

    SettingsModem(device: address, flags: 0x00, values: [:])

  }

  /// The protected command a command's bytes send.
  static func protected(_ command: Command) throws -> ProtectedCommand {

    try #require(ProtectedCommand(command1: command.command1, command2: command.command2))

  }

  // MARK: - The floor

  @Test func namesEveryProtectedCommandByItsBytes() throws {

    #expect(ProtectedCommand(command1: 0x20, command2: 0x0C) == .radioOff)
    #expect(ProtectedCommand(command1: 0x20, command2: 0x0E) == .powerlineOff)
    #expect(ProtectedCommand(command1: 0x20, command2: 0x19) == .checksumOn)
    #expect(ProtectedCommand(command1: 0x20, command2: 0x00) == .programmingLockOn)
    #expect(ProtectedCommand(command1: 0x29, command2: 0x00) == .poke)
    #expect(ProtectedCommand(command1: 0x29, command2: 0xFF) == .poke)

    for command in Self.allowedCommands {

      #expect(ProtectedCommand(command1: command.command1, command2: command.command2) == nil, "\(command)")

    }

    // The catalog's comparison of two catalogs uses the same floor.
    #expect(ProtectedCommand.setOperatingFlagsCommands == DeviceSettingSafety.protectedSetOperatingFlags)
    #expect(ProtectedCommand(command1: DeviceSettingSafety.pokeCommand1, command2: 0x00) == .poke)

    // Set Address MSB and Peek write nothing.
    #expect(ProtectedCommand(command1: 0x28, command2: 0xFF) == nil)
    #expect(ProtectedCommand(command1: 0x2B, command2: 0x00) == nil)

  }

  @Test func protectsExactlyFourSetOperatingFlagsCommandsEachByItsOwnCase() {

    let protected: [UInt8: ProtectedCommand] = (UInt8.min...UInt8.max).reduce(into: [:]) { (found: inout [UInt8: ProtectedCommand], command2: UInt8) in

      found[command2] = ProtectedCommand(command1: 0x20, command2: command2)

    }

    #expect(protected.keys.sorted() == [0x00, 0x0C, 0x0E, 0x19])
    #expect(Set(protected.values).count == 4)
    #expect(!protected.values.contains(.poke))
    #expect(ProtectedCommand.allCases.count == 5)

    for (command2, command) in protected {

      #expect(command.setOperatingFlagsCommand == Command(command1: 0x20, command2: command2), "\(command2)")

    }

    #expect(ProtectedCommand.poke.setOperatingFlagsCommand == nil)

  }

  @Test(arguments: [nil, "exampleFlagless"] as [CommandSetID?])
  func holdsTheFloorWithoutACommandSetOrItsFlags(_ id: CommandSetID?) throws {

    let commands: CommandSet? = try id.map { (id: CommandSetID) -> CommandSet in

      try #require(try DeviceCatalog(json: Data(Self.flaglessJSON.utf8)).commandSet(id: id))

    }

    for command in Self.protectedCommands {

      #expect(DeviceSettingSafety.isNeverSent(command, in: commands), "\(command)")

    }

    for command in Self.allowedCommands {

      #expect(!DeviceSettingSafety.isNeverSent(command, in: commands), "\(command)")

    }

    // A command set's own command with Poke's cmd1 is never sent, whatever cmd2 it's given.
    if let commands, let poke = commands.standardCommand(named: "poke") {

      #expect(!DeviceSettingSafety.isSendable(poke, in: commands))

    }

  }

  // MARK: - Raw device send

  @Test(.timeLimit(.minutes(1)), arguments: Knowledge.allCases, [false, true])
  func refusesEveryProtectedCommandSentAsGiven(_ knowledge: Knowledge, isExtended: Bool) async throws {

    let modem: SettingsModem = Self.modem()
    let network: DeviceNetwork = try self.network(modem, knowing: knowledge)

    for command in Self.protectedCommands {

      let message = DirectMessage(to: Self.address, command1: command.command1, command2: command.command2, data: isExtended ? [] : nil, hasChecksum: true)
      let expected: ProtectedCommand = try Self.protected(command)

      await #expect(throws: SendRefusal.protected(expected), "\(knowledge) \(command)") {

        _ = try await network.send(message, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

      }

    }

    #expect(await modem.standardCommands.isEmpty)
    #expect(await modem.extendedMessages.isEmpty)
    #expect(await modem.flags == 0x00)

  }

  @Test(.timeLimit(.minutes(1)), arguments: Knowledge.allCases)
  func sendsBytesTheFloorDoesntHoldAsGiven(_ knowledge: Knowledge) async throws {

    let modem: SettingsModem = Self.modem()
    let network: DeviceNetwork = try self.network(modem, knowing: knowledge)
    var acknowledged: [Command] = []

    for command in Self.allowedCommands {

      let message = DirectMessage(to: Self.address, command1: command.command1, command2: command.command2, data: nil, hasChecksum: false)

      _ = try await network.send(message, collectingFor: .zero) { (frame: ReceivedFrame) -> Void in

        acknowledged.append(Command(command1: frame.frame[9], command2: frame.frame[10]))

      }

    }

    #expect(await modem.standardCommands == Self.allowedCommands)
    #expect(acknowledged == Self.allowedCommands)

  }

  // MARK: - Device operations

  @Test(.timeLimit(.minutes(1))) func refusesAParameterThatFillsInTheProgrammingLockWithNoFlagForIt() async throws {

    let modem: SettingsModem = Self.modem()
    let device: Device = try network(modem, knowing: .noProgrammingLockFlag).device(Self.address)

    // Off fills setFlags' cmd2 with the protected 0x00, though no flag names it.
    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      try await device.turnOff()

    }

    guard case .unsupported(.turnOff, _)? = error else {

      Issue.record("Expected unsupported, got \(String(describing: error)).")

      return

    }

    #expect(await modem.standardCommands.isEmpty)

    _ = try await device.turnOn()

    #expect(await modem.standardCommands == [Command(command1: 0x11, command2: 0xFF)])

  }

  // MARK: - Keep-awake bytes

  @Test(.timeLimit(.minutes(1)), arguments: Knowledge.allCases, [false, true])
  func refusesEveryProtectedCommandAsKeepAwakeBytes(_ knowledge: Knowledge, isExtended: Bool) async throws {

    let modem: SettingsModem = Self.modem()
    let device: Device = try network(modem, knowing: knowledge).device(Self.address)

    for command in Self.protectedCommands {

      let raw = DeviceLifecycle.HubLinking.RawMessage(command: command, isExtended: isExtended, integrity: isExtended ? .checksum : .unprotected)
      let error: DeviceControlError? = await #expect(throws: DeviceControlError.self, "\(knowledge) \(command)") {

        try await device.sendLinkingMessage(.bytes(raw), duration: nil, writableFlags: [])

      }

      guard case .unsupported(.keepAwake, _)? = error else {

        Issue.record("Expected unsupported, got \(String(describing: error)).")

        return

      }

    }

    #expect(await modem.standardCommands.isEmpty)
    #expect(await modem.extendedMessages.isEmpty)

  }

  @Test(.timeLimit(.minutes(1)), arguments: Knowledge.allCases)
  func sendsKeepAwakeBytesTheFloorDoesntHold(_ knowledge: Knowledge) async throws {

    let modem: SettingsModem = Self.modem()
    let device: Device = try network(modem, knowing: knowledge).device(Self.address)

    for command in Self.allowedCommands {

      try await device.sendLinkingMessage(.bytes(DeviceLifecycle.HubLinking.RawMessage(command: command)), duration: nil, writableFlags: [])

    }

    #expect(await modem.standardCommands == Self.allowedCommands)

  }

  @Test(.timeLimit(.minutes(1))) func neverWritesExtendedSettingsFromKeepAwakeBytes() async throws {

    let modem: SettingsModem = Self.modem()
    let device: Device = try network(modem, knowing: .unknownDevice).device(Self.address)

    // An extended Set with selector 0x05 in D2 writes whatever byte the selector names.
    let set = DeviceLifecycle.HubLinking.RawMessage(
      command: Command(command1: 0x2E, command2: 0x00),
      isExtended: true,
      fixedBytes: [FixedUserDataByte(position: 1, value: 0x01), FixedUserDataByte(position: 2, value: 0x05), FixedUserDataByte(position: 3, value: 0xFF)],
      integrity: .checksum
    )

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      try await device.sendLinkingMessage(.bytes(set), duration: nil, writableFlags: [])

    }

    guard case .unsupported(.keepAwake, _)? = error else {

      Issue.record("Expected unsupported, got \(String(describing: error)).")

      return

    }

    #expect(await modem.extendedMessages.isEmpty)

  }

  @Test(
    .timeLimit(.minutes(1)),
    arguments: [
      // Checksum on's bytes, which a command set with no flags doesn't name.
      DeviceLifecycle.HubLinking.HubMessage.bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x19))),
      // A command the command set doesn't describe.
      DeviceLifecycle.HubLinking.HubMessage.command("noSuchCommand"),
      // An extended Set given by its bytes, which never writes settings.
      DeviceLifecycle.HubLinking.HubMessage.bytes(DeviceLifecycle.HubLinking.RawMessage(
        command: Command(command1: 0x2E, command2: 0x00),
        isExtended: true,
        fixedBytes: [FixedUserDataByte(position: 1, value: 0x01), FixedUserDataByte(position: 2, value: 0x05)],
        integrity: .checksum
      ))
    ]
  )
  func doesntKeepADeviceAwakeThatCantBeLetSleepAgain(_ release: DeviceLifecycle.HubLinking.HubMessage) async throws {

    let modem = InMemoryModem()
    let sensor = InsteonAddress(0x5A, 0x6B, 0x05)
    let identity = ReportedIdentity(category: 0x10, subcategory: 0x7A, firmwareVersion: 0x41)

    // Keeping it awake is allowed, but the release would be refused, each for its own reason.
    let keepAwake = DeviceLifecycle.HubLinking.KeepAwake(
      timing: .afterLinked,
      send: .bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x18))),
      release: release
    )
    let catalog = DeviceCatalog(
      profiles: [
        DeviceProfile(
          model: "9402",
          name: "Example Sleepy Sensor",
          identities: [DeviceIdentity(category: 0x10, subcategory: 0x7A)],
          commandSets: [CommandSetEntry(commandSet: "exampleSleepy", category: 0x10, subcategory: 0x7A)],
          isBatteryPowered: true,
          groups: [DeviceProfile.Group(number: 1, name: "Open", role: .controller)],
          lifecycle: DeviceLifecycle(fromHub: DeviceLifecycle.HubLinking(
            legs: [DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)],
            remoteEnterLinkingMode: DeviceLifecycle.HubLinking.RemoteEnterLinkingMode(works: .yes),
            keepAwake: keepAwake
          ))
        )
      ],
      commandSets: [CommandSet(id: "exampleSleepy", name: "Example", summary: "A command set with no flags.")]
    )
    let network = DeviceNetwork(
      modem: modem,
      catalog: catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [sensor: identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let recorder = LinkingRecorder()

    let result: DeviceLinkingResult = try await network.linking.link(sensor, as: .controller, observer: recorder)

    // Linking goes on, but neither message reaches the sensor.
    #expect(result.links.count == 1)
    #expect(await modem.extendedRequests.isEmpty)
    #expect(await modem.linkingSteps.allSatisfy { (step: InMemoryModem.LinkingStep) -> Bool in

      guard case let .device(_, command, _) = step else {

        return true

      }

      return command.command1 != 0x20

    })
    #expect(await recorder.lines.contains("keep awake: not sent \(sensor)"))
    #expect(await !recorder.lines.contains { (line: String) -> Bool in line.hasPrefix("keep awake: releasing") })

  }

  // MARK: - The catalog's meaning

  /// A made-up keypad whose button lock is turned on with Set Operating Flags `0x19`, the
  /// protected checksum-on byte elsewhere, whose radio mute flag the catalog keeps, and whose
  /// lockout it never sets.
  static let keypadCommands = CommandSet(
    id: "exampleLockableKeypad",
    name: "Example lockable keypad",
    summary: "A button lock turned on with a protected cmd2.",
    operatingFlags: [
      OperatingFlag(name: "lockout", summary: "Locks out linking from the device.", query: .operatingFlags, bit: 0x01, on: 0x00, off: 0x01, label: "Lockout", writeGuard: .neverSet),
      OperatingFlag(name: "radioMute", summary: "Mutes the radio.", query: .operatingFlags, bit: 0x40, on: 0x0C, off: 0x0D, label: "Radio mute", writeGuard: .keep),
      OperatingFlag(name: "buttonLock", summary: "Locks the buttons.", query: .operatingFlags, bit: 0x10, on: 0x19, off: 0x18, label: "Button lock")
    ]
  )

  /// A made-up keypad whose strict checksum flag, which the catalog keeps, is turned on with
  /// Set Operating Flags `0x19`.
  static let strictCommands = CommandSet(
    id: "exampleStrictKeypad",
    name: "Example strict keypad",
    summary: "A kept flag turned on with a protected cmd2.",
    operatingFlags: [
      OperatingFlag(name: "strictChecksum", summary: "Requires a checksum.", query: .operatingFlags, bit: 0x40, on: 0x19, off: 0x18, label: "Strict checksum", writeGuard: .keep)
    ]
  )

  /// A made-up panel whose indicator is lit with Set Operating Flags `0x0C`, the protected
  /// radio-off byte elsewhere, by an extended command with no guard, and whose lockout's on,
  /// `0x00`, is an extended command the catalog never sends.
  static let panelCommands = CommandSet(
    id: "examplePanel",
    name: "Example panel",
    summary: "Set Operating Flags as extended commands.",
    extendedCommands: [
      DeviceExtendedCommand(name: "indicatorOn", summary: "Lights the indicator.", command: Command(command1: 0x20, command2: 0x0C), integrity: .checksum),
      DeviceExtendedCommand(name: "lockoutOn", summary: "Locks out linking.", command: Command(command1: 0x20, command2: 0x00), integrity: .checksum, sendGuard: .never),
      DeviceExtendedCommand(name: "lockoutOff", summary: "Allows linking.", command: Command(command1: 0x20, command2: 0x01), integrity: .checksum)
    ]
  )

  /// A made-up sensor kept awake with flag commands, Set Operating Flags `0x18`, and let sleep
  /// again with `0x19`, the protected checksum-on byte elsewhere.
  static let sensorCommands = CommandSet(
    id: "exampleHiddenSensor",
    name: "Example hidden sensor",
    summary: "Keep-awake flag commands.",
    flagCommands: [
      OperatingFlagCommand(name: "holdAwakeOn", summary: "Keeps the sensor awake.", command2: 0x18),
      OperatingFlagCommand(name: "holdAwakeOff", summary: "Lets the sensor sleep again.", command2: 0x19)
    ]
  )

  /// The made-up keypad's address and identity.
  static let keypad = (address: InsteonAddress(0x3A, 0x4B, 0x42), identity: ReportedIdentity(category: 0x01, subcategory: 0x6A, firmwareVersion: 0x45))

  /// The made-up sensor's address and identity.
  static let sensor = (address: InsteonAddress(0x3A, 0x4B, 0x43), identity: ReportedIdentity(category: 0x10, subcategory: 0x6B, firmwareVersion: 0x41))

  /// The made-up keypad and sensor.
  static let meaningCatalog = DeviceCatalog(
    profiles: [
      ControlExample.profile(model: "9511", name: "Example Lockable Keypad", identity: keypad.identity, commands: keypadCommands, groups: []),
      DeviceProfile(
        model: "9512",
        name: "Example Hidden Sensor",
        identities: [DeviceIdentity(category: sensor.identity.category, subcategory: sensor.identity.subcategory)],
        commandSets: [CommandSetEntry(commandSet: sensorCommands.id, category: sensor.identity.category, subcategory: sensor.identity.subcategory)],
        isBatteryPowered: true,
        groups: [DeviceProfile.Group(number: 1, name: "Open", role: .controller)],
        lifecycle: DeviceLifecycle(fromHub: DeviceLifecycle.HubLinking(
          legs: [DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)],
          isDeviceFirst: true,
          keepAwake: DeviceLifecycle.HubLinking.KeepAwake(timing: .afterLinked, send: .command("holdAwakeOn"), release: .command("holdAwakeOff"))
        ))
      )
    ],
    commandSets: [keypadCommands, strictCommands, panelCommands, sensorCommands]
  )

  /// A network with the made-up catalog that knows a device.
  func meaningNetwork(_ modem: SettingsModem, knowing device: (address: InsteonAddress, identity: ReportedIdentity)) -> DeviceNetwork {

    DeviceNetwork(
      modem: modem,
      catalog: Self.meaningCatalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [device.address: device.identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

  }

  @Test func sendsAProtectedCmd2OnlyWhereTheCommandSetNamesItForAnUnguardedFlag() {

    let checksumOn = Command(command1: 0x20, command2: 0x19)

    // The keypad turns buttonLock on with 0x19.
    #expect(!DeviceSettingSafety.isNeverSent(checksumOn, in: Self.keypadCommands))
    // Its kept radioMute flag's 0x0C, the lockout's 0x00, and 0x0E, which it doesn't name, stay
    // refused.
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0C), in: Self.keypadCommands))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x00), in: Self.keypadCommands))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0E), in: Self.keypadCommands))
    // The strict keypad names 0x19 for strictChecksum, which is kept.
    #expect(DeviceSettingSafety.isNeverSent(checksumOn, in: Self.strictCommands))
    // With no command set, all four are refused.
    #expect(DeviceSettingSafety.floorCommands(in: nil) == ProtectedCommand.setOperatingFlagsCommands)

  }

  @Test func countsAnUnguardedSetOperatingFlagsCommandAsNamingItsCmd2() {

    let panel: CommandSet = Self.panelCommands

    // The panel's indicatorOn is Set Operating Flags 0x0C, an extended command with no guard.
    #expect(panel.extendedCommand(named: "indicatorOn")?.command == Command(command1: 0x20, command2: 0x0C))
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0C), in: panel))
    // Its lockoutOn, 0x00, is guarded, and it names neither 0x0E nor 0x19.
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x00), in: panel))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0E), in: panel))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x19), in: panel))
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x01), in: panel))

  }

  @Test(.timeLimit(.minutes(1))) func sendsAKeypadsButtonLockOnAsGiven() async throws {

    let modem = SettingsModem(device: Self.keypad.address, flags: 0x00, values: [:])
    let network: DeviceNetwork = meaningNetwork(modem, knowing: Self.keypad)
    let buttonLock = DirectMessage(to: Self.keypad.address, command1: 0x20, command2: 0x19, data: nil, hasChecksum: false)
    let radioMute = DirectMessage(to: Self.keypad.address, command1: 0x20, command2: 0x0C, data: nil, hasChecksum: false)

    _ = try await network.send(buttonLock, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    await #expect(throws: SendRefusal.protected(try Self.protected(Command(command1: 0x20, command2: 0x0C)))) {

      _ = try await network.send(radioMute, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    }

    #expect(await modem.standardCommands == [Command(command1: 0x20, command2: 0x19)])

    // The settings page agrees: buttonLock is writable, radioMute isn't.
    let settings: [DeviceSetting] = try await network.device(Self.keypad.address).capabilities().settings
    let writable: [String: Bool] = Dictionary(settings.map { (setting: DeviceSetting) -> (String, Bool) in (setting.key, setting.isWritable) }, uniquingKeysWith: { (first: Bool, _: Bool) -> Bool in first })

    #expect(writable["buttonLock"] == true)
    #expect(writable["radioMute"] == false)

  }

  @Test(.timeLimit(.minutes(1))) func keepsASensorAwakeAndLetsItSleepAgainWithAProtectedCmd2ItNames() async throws {

    let modem = SettingsModem(device: Self.sensor.address, flags: 0x00, values: [:])
    let network: DeviceNetwork = meaningNetwork(modem, knowing: Self.sensor)
    let device: Device = network.device(Self.sensor.address)
    let description: DeviceDescription = try #require(await network.registry.device(Self.sensor.address)?.deviceDescription)
    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake = try #require(description.hubLinking?.keepAwake)
    let release: DeviceLifecycle.HubLinking.HubMessage = try #require(keepAwake.release)
    let writableFlags: Set<SettingName> = DeviceLinkingCoordinator.keepAwakeFlags(of: description)

    // Its release, holdAwakeOff, is 0x19, which its command set names for a flag command.
    try await device.refuseKeepAwakeWithoutRelease(keepAwake, writableFlags: writableFlags)
    try await device.sendLinkingMessage(keepAwake.send, duration: keepAwake.duration, writableFlags: writableFlags)
    try await device.sendLinkingMessage(release, duration: nil, writableFlags: writableFlags)

    let sent: [Command] = await modem.standardCommands.filter { (command: Command) -> Bool in command.command1 == 0x20 }
      + modem.extendedMessages.map(\.command)

    #expect(sent == [Command(command1: 0x20, command2: 0x18), Command(command1: 0x20, command2: 0x19)])

  }

  @Test(.timeLimit(.minutes(1)), arguments: [Knowledge.unknownDevice, .noCatalog])
  func refusesAnExtendedSetAsGivenWithoutACommandSet(_ knowledge: Knowledge) async throws {

    let modem: SettingsModem = Self.modem()
    let network: DeviceNetwork = try self.network(modem, knowing: knowledge)

    // Selector 0x05 may write a byte that holds a guarded flag, such as one that locks out
    // linking; without the catalog, nothing says so.
    let set = DirectMessage(to: Self.address, command1: 0x2E, command2: 0x00, data: [0x01, 0x05, 0x80], hasChecksum: true)

    await #expect(throws: SendRefusal.extendedSetWithoutCommandSet) {

      _ = try await network.send(set, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    }

    #expect(await modem.extendedMessages.isEmpty)

    // An extended Get writes nothing, so it's sent.
    let get = DirectMessage(to: Self.address, command1: 0x2E, command2: 0x00, data: [0x01, 0x00], hasChecksum: true)

    _ = try await network.send(get, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    #expect(await modem.extendedMessages.count == 1)

  }

  // MARK: - Extended data

  /// A network that knows ``CatalogGuardTests``'s device, whose configuration byte holds
  /// guarded flags, written by an extended Set with selector `0x05`, and whose writeFlags
  /// command, D2 `0x07`, writes a flags parameter with guarded bits.
  func guardedNetwork(_ modem: SettingsModem) throws -> DeviceNetwork {

    DeviceNetwork(
      modem: modem,
      catalog: try CatalogGuardTests.catalog(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [CatalogGuardTests.address: CatalogGuardTests.identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

  }

  @Test(.timeLimit(.minutes(1))) func refusesAnExtendedMessageAsGivenThatWritesGuardedFlags() async throws {

    let modem = SettingsModem(device: CatalogGuardTests.address, flags: 0x00, values: [:])
    let network: DeviceNetwork = try guardedNetwork(modem)
    let device: InsteonAddress = CatalogGuardTests.address

    let configuration = DirectMessage(to: device, command1: 0x2E, command2: 0x00, data: [0x01, 0x05, 0x00], hasChecksum: true)

    // Without the device's report, any guarded bit on the byte refuses it, the first named.
    await #expect(throws: SendRefusal.writesGuardedFlags(label: "Beeper lock")) {

      _ = try await network.send(configuration, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    }

    let flagsByte = DirectMessage(to: device, command1: 0x2E, command2: 0x00, data: [0x00, 0x07, 0x00], hasChecksum: true)

    await #expect(throws: SendRefusal.writesGuardedFlags(label: "lockBit")) {

      _ = try await network.send(flagsByte, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    }

    #expect(await modem.extendedMessages.isEmpty)

    // An extended Get writes nothing.
    let get = DirectMessage(to: device, command1: 0x2E, command2: 0x00, data: [0x01, 0x00], hasChecksum: true)

    _ = try await network.send(get, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    #expect(await modem.extendedMessages.count == 1)

  }

  @Test(.timeLimit(.minutes(1))) func refusesBytesTheCatalogNeverSendsToTheDeviceAsGiven() async throws {

    let modem = SettingsModem(device: CatalogGuardTests.address, flags: 0x00, values: [:])
    let network: DeviceNetwork = try guardedNetwork(modem)

    // The catalog's extendedOnly flag is kept, so its off, Set Operating Flags 0x03, which the
    // floor doesn't hold, is never sent.
    let extendedOnlyOff = DirectMessage(to: CatalogGuardTests.address, command1: 0x20, command2: 0x03, data: nil, hasChecksum: false)

    let error: SendRefusal? = await #expect(throws: SendRefusal.self) {

      _ = try await network.send(extendedOnlyOff, collectingFor: .zero) { (_: ReceivedFrame) -> Void in }

    }

    guard case .neverSentToDevice? = error else {

      Issue.record("Expected neverSentToDevice, got \(String(describing: error)).")

      return

    }

    #expect(await modem.standardCommands.isEmpty)

  }

  // MARK: - Raw modem send

  /// Every way the bytes of a command go into a serial command: a standard and an extended
  /// message to the device, and a group command.
  static func serialCommands(carrying command: Command) -> [[UInt8]] {

    let standard: [UInt8] = [0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, command.command1, command.command2]
    let extended: [UInt8] = [0x02, 0x62, 0x3A, 0x4B, 0x41, 0x1F, command.command1, command.command2] + [UInt8](repeating: 0x00, count: 14)
    let group: [UInt8] = [0x02, 0x61, 0x01, command.command1, command.command2]

    return [standard, extended, group]

  }

  @Test(.timeLimit(.minutes(1)), arguments: [false, true])
  func neverWritesAProtectedCommandToTheModem(forcing: Bool) async throws {

    let connection = EchoingConnection()

    try await Modem.withConnection(connection) { (modem: Modem) async throws -> Void in

      let session = ModemSession(modem: modem, hub: nil)

      for command in Self.protectedCommands {

        let expected: ProtectedCommand = try Self.protected(command)

        for bytes in Self.serialCommands(carrying: command) {

          #expect(SerialCommandPolicy.neverWritten(bytes) == .protected(expected), "\(bytes)")

          await #expect(throws: SendRefusal.protected(expected), "\(bytes)") {

            _ = try await session.write(rawCommand: bytes, forcing: forcing, collectingFor: .zero)

          }

        }

      }

    }

    #expect(await connection.written.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func writesAMessageTheFloorDoesntHoldToTheModem() async throws {

    let connection = EchoingConnection()
    let radioOn: [UInt8] = [0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, 0x20, 0x0D]
    let lightOn: [UInt8] = [0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, 0x11, 0xFF]

    try await Modem.withConnection(connection) { (modem: Modem) async throws -> Void in

      let session = ModemSession(modem: modem, hub: nil)

      // Any other Set Operating Flags is refused only unless it's forced.
      let refusal: SendRefusal? = await #expect(throws: SendRefusal.self) {

        _ = try await session.write(rawCommand: radioOn, collectingFor: .zero)

      }

      guard case .serialCommand? = refusal else {

        Issue.record("Expected serialCommand, got \(String(describing: refusal)).")

        return

      }

      _ = try await session.write(rawCommand: radioOn, forcing: true, collectingFor: .zero)
      _ = try await session.write(rawCommand: lightOn, collectingFor: .zero)

    }

    #expect(await connection.written == [radioOn, lightOn])

  }

  @Test func findsAProtectedCommandWhereverAMessageStartsInTheBytes() {

    // Beep, then a whole message: the modem reads both, so --force can't hide the second.
    let hidden: [UInt8] = [0x02, 0x77, 0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, 0x20, 0x0C]

    #expect(SerialCommandPolicy.neverWritten(hidden) == .protected(.radioOff))
    #expect(SerialCommandPolicy.refusal(of: hidden, forcing: true) == .protected(.radioOff))

    // A message cut short, which the next command's bytes could finish.
    #expect(SerialCommandPolicy.neverWritten([0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, 0x20]) == .incompleteMessage)
    #expect(SerialCommandPolicy.neverWritten([0x02, 0x61, 0x01]) == .incompleteMessage)
    #expect(SerialCommandPolicy.refusal(of: [0x02, 0x62, 0x3A], forcing: true) == .incompleteMessage)

    // Bytes that aren't a serial command, and ones that are allowed.
    #expect(SerialCommandPolicy.neverWritten([0x03, 0x60]) == .notSerialCommand)
    #expect(SerialCommandPolicy.neverWritten([0x02, 0x77]) == nil)
    #expect(SerialCommandPolicy.neverWritten([0x02, 0x62, 0x3A, 0x4B, 0x41, 0x0F, 0x11, 0xFF]) == nil)
    #expect(SerialCommandPolicy.refusal(of: [0x02, 0x67], forcing: true) == nil)
    #expect(SerialCommandPolicy.refusal(of: [0x02, 0x67], forcing: false)?.canBeForced == true)
    #expect(SendRefusal.protected(.poke).canBeForced == false)

  }

}

/// A modem connection that echoes each write with an ACK, as a modem accepts a command, and
/// keeps every write.
actor EchoingConnection: ModemConnection {

  /// Every write, in order.
  private(set) var written: [[UInt8]] = []

  private let stream: AsyncThrowingStream<[UInt8], any Error>

  private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation

  init() {

    (stream, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()

  }

  func write(_ bytes: [UInt8]) async throws {

    written.append(bytes)
    continuation.yield(bytes + [0x06])

  }

  nonisolated func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    stream

  }

}
