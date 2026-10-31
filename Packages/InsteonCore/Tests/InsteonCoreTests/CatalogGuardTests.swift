import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// The guards a catalog gives its flags, bits and commands, read from a small made-up catalog
/// in the catalog's own JSON, on ``SettingsModem``: Set Operating Flags `0x0A` and `0x0B` set
/// and clear bit `0x02`, and an extended Set with selector `0x05` writes D3 to the value at D7.
struct CatalogGuardTests {

  let clock: TestClock = TestClock()

  static let address = InsteonAddress(0x3A, 0x4B, 0x21)

  static let identity = ReportedIdentity(category: 0x01, subcategory: 0x76, firmwareVersion: 0x45)

  static let json = #"""
    {
      "devices": [{
        "model": "9201",
        "name": "Example Guarded Switch",
        "identities": [{ "category": "0x01", "subcategory": "0x76" }],
        "commandSets": [{ "commandSet": "exampleGuardedSwitch", "category": "0x01", "subcategory": "0x76" }],
        "groups": [{ "number": "0x01", "name": "Load", "role": "both", "type": "load" }],
        "capabilities": [],
        "sources": ["A"]
      }],
      "commandSets": [{
        "id": "exampleGuardedSwitch",
        "name": "Example guarded switch",
        "description": "Flags, bits and commands the catalog guards.",
        "operatingFlags": [
          { "name": "beeperLock", "description": "Locks the beeper.", "query": "0x00", "bit": "0x02", "on": "0x0A", "off": "0x0B", "guard": "neverSet", "label": "Beeper lock" },
          { "name": "extendedOnly", "description": "Takes only extended messages.", "query": "0x00", "bit": "0x04", "on": "0x02", "off": "0x03", "guard": "keep", "label": "Extended only" },
          { "name": "newerGuard", "description": "Guarded by a later version.", "query": "0x00", "bit": "0x08", "on": "0x06", "off": "0x07", "guard": "somethingNewer", "label": "Newer guard" },
          { "name": "keyBeep", "description": "Beeps.", "query": "0x00", "bit": "0x01", "on": "0x0C", "off": "0x0D", "label": "Key beep" },
          { "name": "chime", "description": "Chimes.", "query": "0x00", "bit": "0x20", "onCommand": "chimeOn", "offCommand": "chimeOff", "label": "Chime" },
          { "name": "radioOff", "description": "Turns the radio off.", "query": "0x00", "bit": "0x40", "on": "0x0E", "off": "0x0F", "guard": "neverSet", "label": "Radio off" },
          { "name": "programmingLock", "description": "Locks programming.", "query": "0x00", "bit": "0x80", "on": "0x10", "off": "0x11", "label": "Programming lock" }
        ],
        "flagCommands": [
          { "name": "lockOn", "description": "Locks the device.", "command2": "0x0C", "guard": "never" }
        ],
        "standardCommands": [
          { "name": "lightOn", "description": "On.", "command1": "0x11", "command2": "0xFF" },
          { "name": "lightOff", "description": "Off.", "command1": "0x13", "command2": "0x00" },
          { "name": "chimeOn", "description": "Chimes.", "command1": "0x45", "command2": "0x01", "guard": "never" },
          { "name": "chimeOff", "description": "Stops chiming.", "command1": "0x45", "command2": "0x00" }
        ],
        "extendedCommands": [
          { "name": "writeFlags", "description": "Writes the flags byte.", "command1": "0x2E", "command2": "0x00",
            "fixed": [{ "position": 2, "value": "0x07" }],
            "parameters": [{ "name": "flagsByte", "description": "The flags.", "byte": 3, "kind": "flags",
              "bits": [
                { "mask": "0x01", "name": "lockBit", "guard": "neverSet" },
                { "mask": "0x02", "name": "keepBit", "guard": "keep" },
                { "mask": "0x04", "name": "freeBit" }
              ] }] },
          { "name": "sleepNever", "description": "Locks while asleep.", "command1": "0x20", "command2": "0x00", "integrity": "checksum",
            "parameters": [{ "name": "sleep", "description": "The sleep.", "byte": 3 }], "guard": "never" }
        ],
        "extendedSettings": {
          "perButton": false,
          "values": [
            { "name": "configuration", "description": "The operating flags byte.", "byte": 7, "flagsQuery": "0x00", "label": "Configuration" },
            { "name": "flagsByte", "description": "Flags another command writes.", "byte": 8, "write": "writeFlags", "label": "Flags byte" },
            { "name": "sleep", "description": "A sleep setting.", "byte": 9, "write": "sleepNever", "label": "Sleep" }
          ],
          "writes": [
            { "name": "configuration", "description": "Sets the configuration.", "selector": "0x05", "perButton": false,
              "bytes": [{ "position": 3, "value": "configuration" }] }
          ]
        },
        "groupTypes": [{
          "name": "load",
          "label": "Load",
          "kind": "relay",
          "actions": [
            { "name": "on", "label": "On", "command": "lightOn" },
            { "name": "chime", "label": "Chime", "command": "chimeOn" }
          ]
        }],
        "sources": ["A"]
      }]
    }
    """#

  static func catalog() throws -> DeviceCatalog {

    try DeviceCatalog(json: Data(json.utf8))

  }

  func device(_ modem: SettingsModem) throws -> Device {

    let network = DeviceNetwork(
      modem: modem,
      catalog: try Self.catalog(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [Self.address: Self.identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    return network.device(Self.address)

  }

  /// Writes a setting, expecting a refusal.
  func refusal(_ key: String, to text: String, on modem: SettingsModem) async throws -> DeviceSettingError? {

    let device: Device = try self.device(modem)

    return await #expect(throws: DeviceSettingError.self) {

      _ = try await device.writeSetting(key, to: text)

    }

  }

  /// The label of a refusal to write a setting that's never written, or `nil` for any other
  /// error.
  static func neverWrittenLabel(_ error: DeviceSettingError?) -> String? {

    guard case let .neverWritten(label)? = error else {

      return nil

    }

    return label

  }

  /// The label of a refusal to set a flag that's never set, or `nil` for any other error.
  static func lockedLabel(_ error: DeviceSettingError?) -> String? {

    guard case let .leavesProgrammingLocked(label)? = error else {

      return nil

    }

    return label

  }

  // MARK: - Flags

  @Test(.timeLimit(.minutes(1))) func neverSetsAFlagTheCatalogGuardsAsNeverSet() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [:])
    let error: DeviceSettingError? = try await refusal("beeperLock", to: "on", on: modem)

    guard case let .leavesProgrammingLocked(label)? = error else {

      Issue.record("Expected leavesProgrammingLocked, got \(String(describing: error)).")

      return

    }

    #expect(label == "Beeper lock")
    #expect(await modem.standardCommands.isEmpty)
    #expect(await modem.flags == 0x00)

  }

  @Test(.timeLimit(.minutes(1))) func clearsAFlagTheCatalogGuardsAsNeverSet() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x02, values: [:])

    let change: DeviceSettingChange = try await device(modem).writeSetting("beeperLock", to: "off")

    #expect(change.isConfirmed)
    #expect(await modem.flags == 0x00)

  }

  @Test(.timeLimit(.minutes(1)), arguments: ["extendedOnly", "newerGuard"])
  func neverChangesAFlagTheCatalogKeeps(key: String) async throws {

    for state in ["on", "off"] {

      let modem = SettingsModem(device: Self.address, flags: 0x00, values: [:])
      let error: DeviceSettingError? = try await refusal(key, to: state, on: modem)

      guard case .neverWritten? = error else {

        Issue.record("Expected neverWritten for \(key) \(state), got \(String(describing: error)).")

        return

      }

      #expect(await modem.standardCommands.isEmpty)
      #expect(await modem.extendedMessages.isEmpty)

    }

  }

  @Test(.timeLimit(.minutes(1))) func keepsTheFloorWhereTheCatalogsGuardIsWeakerOrMissing() async throws {

    // The catalog guards the radio only as never set, and gives the programming lock no guard.
    let radio = SettingsModem(device: Self.address, flags: 0x40, values: [:])
    let radioError: DeviceSettingError? = try await refusal("radioOff", to: "off", on: radio)

    #expect(Self.neverWrittenLabel(radioError) == "Radio off")
    #expect(await radio.standardCommands.isEmpty)

    let lock = SettingsModem(device: Self.address, flags: 0x00, values: [:])
    let lockError: DeviceSettingError? = try await refusal("programmingLock", to: "on", on: lock)

    #expect(Self.lockedLabel(lockError) == "Programming lock")
    #expect(await lock.standardCommands.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func neverSendsAFlagsCommandWithTheBytesOfOneTheCatalogNeverSends() async throws {

    // Key beep on is Set Operating Flags 0x0C, the bytes of the never-sent lockOn.
    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [:])
    let error: DeviceSettingError? = try await refusal("keyBeep", to: "on", on: modem)

    #expect(Self.neverWrittenLabel(error) == "Key beep")
    #expect(await modem.standardCommands.isEmpty)

    // Its off command isn't guarded.
    let off: DeviceSettingChange = try await device(modem).writeSetting("keyBeep", to: "off")

    #expect(off.isConfirmed)
    #expect(await modem.standardCommands.contains(Command(command1: 0x20, command2: 0x0D)))

  }

  @Test(.timeLimit(.minutes(1))) func neverSendsAStandardCommandTheCatalogNeverSends() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [:])
    let error: DeviceSettingError? = try await refusal("chime", to: "on", on: modem)

    #expect(Self.neverWrittenLabel(error) == "Chime")
    #expect(await modem.standardCommands.isEmpty)

  }

  // MARK: - Values

  @Test(.timeLimit(.minutes(1)), arguments: [(UInt8(0x02), "Beeper lock"), (0x80, "Programming lock")])
  func neverSetsANeverSetBitThroughAValueThatHoldsTheFlags(bit: UInt8, label: String) async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [7: 0x00])
    let text: String = "0x" + (bit < 0x10 ? "0" : "") + String(bit, radix: 16, uppercase: true)
    let error: DeviceSettingError? = try await refusal("configuration", to: text, on: modem)

    #expect(Self.lockedLabel(error) == label)
    #expect(await modem.extendedMessages.isEmpty)
    #expect(await modem.values[7] == 0x00)

  }

  @Test(.timeLimit(.minutes(1)), arguments: [UInt8(0x04), 0x08, 0x40])
  func neverChangesAKeptBitThroughAValueThatHoldsTheFlags(bit: UInt8) async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [7: 0x00])
    let text: String = "0x" + (bit < 0x10 ? "0" : "") + String(bit, radix: 16, uppercase: true)
    let error: DeviceSettingError? = try await refusal("configuration", to: text, on: modem)

    guard case .neverWritten? = error else {

      Issue.record("Expected neverWritten for bit \(bit), got \(String(describing: error)).")

      return

    }

    // Only the extended Get that read the byte was sent.
    #expect(await modem.extendedMessages.allSatisfy { (message: ExtendedMessage) -> Bool in message.userData[2] == 0x00 })
    #expect(await modem.values[7] == 0x00)

  }

  @Test(.timeLimit(.minutes(1))) func writesAValueThatHoldsTheFlagsWhenItLeavesTheGuardedBitsAsTheyAre() async throws {

    // The radio's bit is set already and stays set; bit 0x01 is key beep, which isn't guarded.
    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [7: 0x40])

    let change: DeviceSettingChange = try await device(modem).writeSetting("configuration", to: "0x41")

    #expect(change.isConfirmed)
    #expect(await modem.values[7] == 0x41)

  }

  @Test(.timeLimit(.minutes(1))) func neverSetsANeverSetBitOfAFlagsParameter() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [8: 0x00])
    let error: DeviceSettingError? = try await refusal("flagsByte", to: "0x01", on: modem)

    #expect(Self.lockedLabel(error) == "lockBit")
    #expect(await modem.extendedMessages.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func neverChangesAKeptBitOfAFlagsParameter() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [8: 0x00])
    let error: DeviceSettingError? = try await refusal("flagsByte", to: "0x02", on: modem)

    #expect(Self.neverWrittenLabel(error) == "keepBit")
    #expect(await modem.extendedMessages.allSatisfy { (message: ExtendedMessage) -> Bool in message.userData[2] == 0x00 })

  }

  @Test(.timeLimit(.minutes(1))) func neverWritesAValueWhoseCommandTheCatalogNeverSends() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [9: 0x00])
    let error: DeviceSettingError? = try await refusal("sleep", to: "0x01", on: modem)

    #expect(Self.neverWrittenLabel(error) == "Sleep")
    #expect(await modem.standardCommands.isEmpty)
    #expect(await modem.extendedMessages.isEmpty)

  }

  // MARK: - What's shown and sent

  @Test(.timeLimit(.minutes(1))) func showsTheSettingsTheCatalogGuardsAsReadOnly() async throws {

    let modem = SettingsModem(device: Self.address, flags: 0x00, values: [:])
    let capabilities: DeviceCapabilities = try await device(modem).capabilities()
    let writable: [String: Bool] = Dictionary(uniqueKeysWithValues: capabilities.settings.map { (setting: DeviceSetting) -> (String, Bool) in

      (setting.key, setting.isWritable)

    })

    #expect(writable == [
      "beeperLock": true,
      "extendedOnly": false,
      "newerGuard": false,
      "keyBeep": true,
      "chime": true,
      "radioOff": false,
      "programmingLock": true,
      "configuration": true,
      "flagsByte": true,
      "sleep": false
    ])

  }

  @Test func leavesCommandsTheCatalogNeverSendsOutOfTheControlModel() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x01, subcategory: 0x76, firmwareVersion: 0x45)
    let model: DeviceControlModel = DeviceControlModel.make(description)

    #expect(model.standardCommand(named: "lightOn") != nil)
    #expect(model.standardCommand(named: "chimeOn") == nil)
    #expect(model.standardCommand(named: "chimeOff") != nil)
    #expect(model.extendedCommand(named: "writeFlags") != nil)
    #expect(model.extendedCommand(named: "sleepNever") == nil)

  }

}
