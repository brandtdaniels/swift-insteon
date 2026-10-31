import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Every message a ``Device`` sends is checked by the bytes it carries against those never
/// sent to the device, derived from its command set's guarded and floor flags and commands,
/// on ``SettingsModem``.
struct GuardedSendTests {

  let clock: TestClock = TestClock()

  static let address = InsteonAddress(0x3A, 0x4B, 0x31)

  static let identity = ReportedIdentity(category: 0x01, subcategory: 0x75, firmwareVersion: 0x45)

  /// A command set with no guards at all: its programming lock is set with Set Operating Flags
  /// `0x00` and its radio turned off with `0x0C`, which only the floor's flag names guard. Its
  /// load's off action fills a Set Operating Flags cmd2 with the caller's value, and its Beep
  /// has the radio off flag's bytes.
  static let json = #"""
    {
      "devices": [{
        "model": "9301",
        "name": "Example Unguarded Switch",
        "identities": [{ "category": "0x01", "subcategory": "0x75" }],
        "commandSets": [{ "commandSet": "exampleUnguarded", "category": "0x01", "subcategory": "0x75" }],
        "groups": [{ "number": "0x01", "name": "Load", "role": "both", "type": "load" }],
        "capabilities": [],
        "sources": ["A"]
      }],
      "commandSets": [{
        "id": "exampleUnguarded",
        "name": "Example unguarded switch",
        "description": "Commands that reach never-sent bytes under other names.",
        "operatingFlags": [
          { "name": "programmingLock", "description": "Locks programming.", "query": "0x00", "bit": "0x01", "on": "0x00", "off": "0x01" },
          { "name": "radioOff", "description": "Turns the radio off.", "query": "0x00", "bit": "0x40", "on": "0x0C", "off": "0x0D" }
        ],
        "standardCommands": [
          { "name": "lightOn", "description": "On.", "command1": "0x11", "command2": "0xFF" },
          { "name": "setFlags", "description": "Set Operating Flags with a cmd2 the caller gives.", "command1": "0x20",
            "parameter": { "name": "flags", "description": "The cmd2." } },
          { "name": "beep", "description": "Not a beep at all.", "command1": "0x20", "command2": "0x0C" }
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

  func device(_ modem: SettingsModem) throws -> Device {

    let network = DeviceNetwork(
      modem: modem,
      catalog: try DeviceCatalog(json: Data(Self.json.utf8)),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [Self.address: Self.identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    return network.device(Self.address)

  }

  @Test(.timeLimit(.minutes(1))) func refusesAParameterThatFillsInNeverSentBytes() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [:])
    let device: Device = try self.device(modem)

    // Off fills setFlags' cmd2 with 0x00: Set Operating Flags 0x00, the programming lock on.
    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      try await device.turnOff()

    }

    guard case .unsupported(.turnOff, _)? = error else {

      Issue.record("Expected unsupported, got \(String(describing: error)).")

      return

    }

    #expect(await modem.standardCommands.isEmpty)
    #expect(await modem.flags == 0x00)

    // On isn't guarded.
    _ = try await device.turnOn()

    #expect(await modem.standardCommands == [Command(command1: 0x11, command2: 0xFF)])

  }

  @Test(.timeLimit(.minutes(1))) func refusesABeepWithTheBytesOfAFlagThatsNeverWritten() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [:])
    let device: Device = try self.device(modem)

    let error: DeviceControlError? = await #expect(throws: DeviceControlError.self) {

      try await device.beep()

    }

    guard case .unsupported(.beep, _)? = error else {

      Issue.record("Expected unsupported, got \(String(describing: error)).")

      return

    }

    #expect(await modem.standardCommands.isEmpty)
    #expect(try await device.capabilities().canBeep == false)

  }

  @Test func derivesNeverSentBytesFromTheFloorWhereTheCatalogGivesNoGuards() throws {

    let commands: CommandSet = try #require(try DeviceCatalog(json: Data(Self.json.utf8)).commandSet(id: "exampleUnguarded"))

    #expect(DeviceSettingSafety.neverSentCommands(in: commands) == [
      Command(command1: 0x20, command2: 0x00),
      Command(command1: 0x20, command2: 0x0C),
      Command(command1: 0x20, command2: 0x0D)
    ])
    // The programming lock is still turned off.
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x01), in: commands))

  }

  @Test func refusesTheBundledCatalogsFloorBytesUnderAnyName() throws {

    let catalog: DeviceCatalog = try DeviceCatalog.bundled()
    let tempLinc: CommandSet = try #require(catalog.commandSet(id: "tempLinc"))
    let scheduleTimer: CommandSet = try #require(catalog.commandSet(id: "keypadLincScheduleTimer"))
    let outdoor: CommandSet = try #require(catalog.commandSet(id: "outdoorApplianceLinc"))
    let keypad: CommandSet = try #require(catalog.commandSet(id: "keypadLinc"))

    // The thermostat's extended programmingLockOn is Set Operating Flags 0x00, which the
    // catalog guards and the floor names, with no flag to derive it from.
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x00), in: tempLinc))
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x01), in: tempLinc))
    #expect(tempLinc.extendedCommand(named: "programmingLockOn").map { DeviceSettingSafety.isSendable($0, in: tempLinc) } == false)
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x00), in: scheduleTimer))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0C), in: outdoor))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0E), in: outdoor))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x19), in: outdoor))
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0D), in: outdoor))
    // A keypad's radio off flag guards both its cmd2s, and its programming lock's on.
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0C), in: keypad))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0D), in: keypad))
    #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x00), in: keypad))
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0A), in: keypad))
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x11, command2: 0xFF), in: keypad))

  }

  // MARK: - The bundled catalog's own guards

  @Test func refusesEveryGuardTheBundledCatalogGives() throws {

    let catalog: DeviceCatalog = try DeviceCatalog.bundled()
    var guardedFlags: Int = 0
    var guardedFlagCommands: Int = 0
    var guardedExtendedCommands: Int = 0
    var guardedBits: Int = 0

    for commands in catalog.commandSets {

      let never: Set<Command> = DeviceSettingSafety.neverSentCommands(in: commands)

      for flag in commands.operatingFlags {

        guard let writeGuard = flag.writeGuard else {

          continue

        }

        guardedFlags += 1

        let rule: DeviceSettingSafety.Rule? = DeviceSettingSafety.rule(for: flag)

        // A guard is never weakened: never set stays at least never set, and anything else is kept.
        #expect(rule == .keep || (writeGuard == .neverSet && rule == .neverSet), "\(commands.id) \(flag.name)")

        if let on = flag.on {

          #expect(never.contains(Command(command1: 0x20, command2: on)), "\(commands.id) \(flag.name) on")

        }

        if rule == .keep, let off = flag.off {

          #expect(never.contains(Command(command1: 0x20, command2: off)), "\(commands.id) \(flag.name) off")

        }

      }

      for flagCommand in commands.flagCommands where flagCommand.sendGuard != nil {

        guardedFlagCommands += 1

        #expect(never.contains(flagCommand.command.command), "\(commands.id) \(flagCommand.name)")

      }

      for standard in commands.standardCommands where standard.sendGuard != nil {

        #expect(!DeviceSettingSafety.isSendable(standard, in: commands), "\(commands.id) \(standard.name)")

      }

      for extended in commands.extendedCommands {

        if extended.sendGuard != nil {

          guardedExtendedCommands += 1

          #expect(!DeviceSettingSafety.isSendable(extended, in: commands), "\(commands.id) \(extended.name)")

        }

        for parameter in extended.parameters {

          guard case let .flags(bits) = parameter.kind else {

            continue

          }

          for bit in bits {

            guard let writeGuard = bit.writeGuard else {

              continue

            }

            guardedBits += 1

            let rule: DeviceSettingSafety.Rule? = DeviceSettingSafety.rule(named: bit.name, writeGuard: writeGuard)

            #expect(rule == .keep || (writeGuard == .neverSet && rule == .neverSet), "\(commands.id) \(extended.name) \(bit.name)")

          }

        }

      }

    }

    // The bundled catalog gives guards of every kind, so none of the loops above is empty.
    #expect(guardedFlags > 0)
    #expect(guardedFlagCommands > 0)
    #expect(guardedExtendedCommands > 0)
    #expect(guardedBits > 0)

  }

  @Test func refusesTheBundledOutdoorPlugsRadioOffAndAnI3ProgrammingLockBit() throws {

    let catalog: DeviceCatalog = try DeviceCatalog.bundled()

    // The outdoor plug's radioOff is a flag command, Set Operating Flags 0x0C, that the catalog
    // never sends, in both of its command sets; radioOn isn't guarded.
    for id: CommandSetID in ["outdoorApplianceLinc", "outdoorApplianceLincFirmware42"] {

      let outdoor: CommandSet = try #require(catalog.commandSet(id: id))
      let radioOff: OperatingFlagCommand = try #require(outdoor.flagCommands.first { (command: OperatingFlagCommand) -> Bool in command.name == "radioOff" })

      #expect(radioOff.sendGuard == .never)
      #expect(radioOff.command.command == Command(command1: 0x20, command2: 0x0C))
      #expect(DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0C), in: outdoor))
      #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x0D), in: outdoor))

    }

    // An i3 paddle's writeProperties holds the 0x00 flags in its flags00 parameter: the
    // programming lock's bit is never set, and the radio's is kept.
    let paddle: CommandSet = try #require(catalog.commandSet(id: "i3Paddle"))
    let writeProperties: DeviceExtendedCommand = try #require(paddle.extendedCommand(named: "writeProperties"))
    let flags00: MessageField = try #require(writeProperties.parameters.first { (field: MessageField) -> Bool in field.name == "flags00" })

    guard case let .flags(bits) = flags00.kind else {

      Issue.record("Expected flags00 to be flags, got \(String(describing: flags00.kind)).")

      return

    }

    let lock: FieldBit = try #require(bits.first { (bit: FieldBit) -> Bool in bit.name == "programmingLock" })
    let radio: FieldBit = try #require(bits.first { (bit: FieldBit) -> Bool in bit.name == "radioOff" })

    #expect(lock.mask == 0x01)
    #expect(lock.writeGuard == .neverSet)
    #expect(DeviceSettingSafety.rule(named: lock.name, writeGuard: lock.writeGuard) == .neverSet)
    #expect(radio.mask == 0x40)
    #expect(radio.writeGuard == .keep)
    #expect(DeviceSettingSafety.rule(named: radio.name, writeGuard: radio.writeGuard) == .keep)

  }

  /// A device the bundled catalog describes, on a ``SettingsModem`` with its flags clear.
  func bundledDevice(_ address: InsteonAddress, identity: ReportedIdentity, modem: SettingsModem) throws -> Device {

    let network = DeviceNetwork(
      modem: modem,
      catalog: try DeviceCatalog.bundled(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    return network.device(address)

  }

  @Test(.timeLimit(.minutes(1))) func neverLocksOrSilencesABundledI3Paddle() async throws {

    // The bundled catalog's i3 paddle, 0x01/0x57: its programming lock is never set and its
    // radio off flag is kept.
    let paddle = InsteonAddress(0x3A, 0x4B, 0x32)
    let modem = SettingsModem(device: paddle, flags: 0x00, values: [:])
    let device: Device = try bundledDevice(paddle, identity: ReportedIdentity(category: 0x01, subcategory: 0x57, firmwareVersion: 0x45), modem: modem)

    let lock: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await device.writeSetting("programmingLock", to: "on")

    }

    guard case .leavesProgrammingLocked? = lock else {

      Issue.record("Expected leavesProgrammingLocked, got \(String(describing: lock)).")

      return

    }

    let radio: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await device.writeSetting("radioOff", to: "on")

    }

    guard case .neverWritten? = radio else {

      Issue.record("Expected neverWritten, got \(String(describing: radio)).")

      return

    }

    #expect(await modem.standardCommands.isEmpty)
    #expect(await modem.extendedMessages.isEmpty)
    #expect(await modem.flags == 0x00)

  }

  @Test(.timeLimit(.minutes(1))) func neverLocksABundledOutdoorPlugRunningFirmware42() async throws {

    // The bundled catalog's outdoor plug, 0x02/0x38, whose firmware 0x42 has a programming
    // lock flag the catalog guards as never set.
    let plug = InsteonAddress(0x3A, 0x4B, 0x33)
    let modem = SettingsModem(device: plug, flags: 0x00, values: [:])
    let device: Device = try bundledDevice(plug, identity: ReportedIdentity(category: 0x02, subcategory: 0x38, firmwareVersion: 0x42), modem: modem)

    let error: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await device.writeSetting("programmingLock", to: "on")

    }

    guard case .leavesProgrammingLocked? = error else {

      Issue.record("Expected leavesProgrammingLocked, got \(String(describing: error)).")

      return

    }

    #expect(await modem.standardCommands.isEmpty)
    #expect(await modem.extendedMessages.isEmpty)

  }

}
