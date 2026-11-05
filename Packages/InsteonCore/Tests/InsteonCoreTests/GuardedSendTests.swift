import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Every message a ``Device`` sends is checked by the bytes it carries against those never
/// sent to the device, derived from its command set's guarded flags and commands and the byte
/// floor, on ``SettingsModem``.
struct GuardedSendTests {

  let clock: TestClock = TestClock()

  static let address = InsteonAddress(0x3A, 0x4B, 0x31)

  static let identity = ReportedIdentity(category: 0x01, subcategory: 0x75, firmwareVersion: 0x45)

  /// A command set whose lockout, never set, is turned on with Set Operating Flags `0x00`, and
  /// whose radio mute, kept, is turned on with `0x0C` and off with `0x0D`. Its load's off action
  /// fills a Set Operating Flags cmd2 with the caller's value, and its Beep has the radio mute
  /// flag's bytes.
  static let json = #"""
    {
      "devices": [{
        "model": "9301",
        "name": "Example Guarded Relay",
        "identities": [{ "category": "0x01", "subcategory": "0x75" }],
        "commandSets": [{ "commandSet": "exampleGuardedRelay", "category": "0x01", "subcategory": "0x75" }],
        "groups": [{ "number": "0x01", "name": "Load", "role": "both", "type": "load" }],
        "capabilities": [],
        "sources": ["A"]
      }],
      "commandSets": [{
        "id": "exampleGuardedRelay",
        "name": "Example guarded relay",
        "description": "Commands that reach never-sent bytes under other names.",
        "operatingFlags": [
          { "name": "lockout", "description": "Locks out linking from the device.", "query": "0x00", "bit": "0x01", "on": "0x00", "off": "0x01", "guard": "neverSet" },
          { "name": "radioMute", "description": "Mutes the radio.", "query": "0x00", "bit": "0x40", "on": "0x0C", "off": "0x0D", "guard": "keep" }
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

    // Off fills setFlags' cmd2 with 0x00: Set Operating Flags 0x00, the lockout on.
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

  @Test func derivesNeverSentBytesFromTheCatalogsGuardsAndTheByteFloor() throws {

    let commands: CommandSet = try #require(try DeviceCatalog(json: Data(Self.json.utf8)).commandSet(id: "exampleGuardedRelay"))

    // The byte floor's 0x0E and 0x19 are there too, with no flag to name them.
    #expect(DeviceSettingSafety.neverSentCommands(in: commands) == [
      Command(command1: 0x20, command2: 0x00),
      Command(command1: 0x20, command2: 0x0C),
      Command(command1: 0x20, command2: 0x0D),
      Command(command1: 0x20, command2: 0x0E),
      Command(command1: 0x20, command2: 0x19)
    ])
    // The lockout is still turned off.
    #expect(!DeviceSettingSafety.isNeverSent(Command(command1: 0x20, command2: 0x01), in: commands))

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

            let rule: DeviceSettingSafety.Rule? = DeviceSettingSafety.rule(for: writeGuard)

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

}
