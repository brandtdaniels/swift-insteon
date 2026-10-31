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

    // The thermostat's extended programmingLockOn is Set Operating Flags 0x00, with no guard in
    // the catalog and no flag to derive it from.
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

}
