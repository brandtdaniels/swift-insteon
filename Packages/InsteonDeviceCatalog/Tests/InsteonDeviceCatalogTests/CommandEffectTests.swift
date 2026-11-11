import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// What a command does to its addressee and whether it may be sent again, as a command set's
/// entries carry them, read from a made-up command set.
struct CommandEffectTests {

  static let commandSet = #"""
    {
      "id": "testEffects",
      "name": "Test Effects",
      "description": "A made-up command set whose entries carry effects.",
      "operatingFlags": [
        { "name": "glowTrim", "description": "Trims the glow.", "query": "0x00", "bit": "0x04", "on": "0x40", "off": "0x41" }
      ],
      "flagCommands": [
        { "name": "glowPulse", "description": "Pulses the glow.", "command2": "0x40", "effect": "configuration", "idempotent": false },
        { "name": "chimeQuiet", "description": "Quiets the chime.", "command2": "0x42", "effect": "configuration", "idempotent": true },
        { "name": "chimeUnmarked", "description": "Marks nothing.", "command2": "0x44" }
      ],
      "standardCommands": [
        { "name": "chimeQuietStandard", "description": "Quiets the chime and clears its counter.", "command1": "0x20", "command2": "0x42",
          "effect": "destructive", "idempotent": true },
        { "name": "loadLevel", "description": "Sets the load's level.", "command1": "0x11", "extendedWhen": "glowTrim",
          "effect": "actuation", "idempotent": true,
          "parameter": { "name": "level", "description": "The level." } },
        { "name": "pickTone", "description": "Picks a tone.", "command1": "0x30", "effect": "configuration", "idempotent": true,
          "parameter": { "name": "tone", "description": "The tone.", "kind": "enumeration", "enumeration": "tones" } },
        { "name": "stepUp", "description": "Steps the load up.", "command1": "0x15", "command2": "0x00", "effect": "actuation", "idempotent": false },
        { "name": "readLevel", "description": "Reads the level.", "command1": "0x19", "command2": "0x00", "effect": "readOnly", "idempotent": true },
        { "name": "sideways", "description": "Does something newer.", "command1": "0x31", "command2": "0x01", "effect": "sideEffect", "idempotent": true },
        { "name": "unmarked", "description": "Marks nothing.", "command1": "0x32", "command2": "0x02" },
        { "name": "pairedSettle", "description": "Settles a pairing.", "command1": "0x33", "command2": "0x03", "effect": "link", "idempotent": true },
        { "name": "pairedBlink", "description": "Blinks a pairing.", "command1": "0x33", "command2": "0x03", "effect": "actuation", "idempotent": true }
      ],
      "extendedCommands": [
        { "name": "readBlock", "description": "Reads a block.", "command1": "0x2E", "command2": "0x02",
          "effect": "readOnly", "idempotent": true },
        { "name": "writeBlock", "description": "Writes a block.", "command1": "0x2E", "command2": "0x02", "integrity": "checksum",
          "fixed": [{ "position": 2, "value": "0x02" }],
          "parameters": [{ "name": "block", "description": "The block.", "byte": 3 }],
          "effect": "configuration", "idempotent": true },
        { "name": "buttonGlow", "description": "Sets a button's glow.", "command1": "0x2F", "command2": "0x00", "perButton": true, "integrity": "crc",
          "fixed": [{ "position": 2, "value": "0x05" }],
          "parameters": [{ "name": "glow", "description": "The glow.", "byte": 4 }],
          "effect": "configuration", "idempotent": true }
      ],
      "extendedSettings": {
        "perButton": false,
        "values": [{ "name": "trim", "description": "The trim.", "byte": 3 }],
        "writes": [{ "name": "writeTrim", "description": "Writes the trim.", "selector": "0x06", "perButton": false,
          "bytes": [{ "position": 3, "value": "trim" }] }]
      },
      "enumerations": [
        { "name": "tones", "values": [{ "value": "0x01", "name": "low" }, { "value": "0x02", "name": "high" }] }
      ],
      "sources": ["A"]
    }
    """#

  static let sensor = #"""
    {
      "model": "1",
      "name": "Test Sensor",
      "identities": [{ "category": "0x10", "subcategory": "0x01" }],
      "batteryPowered": true,
      "groups": [{ "number": "0x01", "name": "Open", "role": "controller" }],
      "capabilities": [],
      "lifecycle": {
        "fromHub": {
          "legs": [{ "modem": "responder", "modemGroup": "0x01", "deviceGroup": "0x01" }],
          "deviceFirst": true,
          "keepAwake": {
            "when": "afterLinked",
            "send": { "command1": "0x20", "command2": "0x46", "extended": true, "integrity": "checksum",
                      "effect": "configuration", "idempotent": true },
            "release": { "command1": "0x20", "command2": "0x47" }
          }
        }
      },
      "sources": ["A"]
    }
    """#

  static func catalog() throws -> DeviceCatalog {

    let json: String = #"{ "devices": [\#(sensor)], "commandSets": [\#(commandSet)] }"#

    return try DeviceCatalog(json: Data(json.utf8))

  }

  static func commands() throws -> CommandSet {

    try #require(try catalog().commandSet(id: "testEffects"))

  }

  // MARK: - Decoding

  @Test func readsTheEffectAndIdempotentOfEachKindOfCommand() throws {

    let commands = try Self.commands()

    let flagCommand = try #require(commands.flagCommands.first { $0.name == "chimeQuiet" })
    #expect(flagCommand.effect == .configuration)
    #expect(flagCommand.isIdempotent == true)

    let standard = try #require(commands.standardCommand(named: "stepUp"))
    #expect(standard.effect == .actuation)
    #expect(standard.isIdempotent == false)

    let extended = try #require(commands.extendedCommand(named: "readBlock"))
    #expect(extended.effect == .readOnly)
    #expect(extended.isIdempotent == true)

  }

  @Test func readsAMissingEffectAndIdempotentAsNone() throws {

    let commands = try Self.commands()

    let flagCommand = try #require(commands.flagCommands.first { $0.name == "chimeUnmarked" })
    #expect(flagCommand.effect == nil)
    #expect(flagCommand.isIdempotent == nil)

    let standard = try #require(commands.standardCommand(named: "unmarked"))
    #expect(standard.effect == nil)
    #expect(standard.isIdempotent == nil)

  }

  @Test func keepsAnEffectFromALaterVersionOfTheCatalogAndRanksItDestructive() throws {

    let effect = try #require(try Self.commands().standardCommand(named: "sideways")?.effect)

    #expect(effect.rawValue == "sideEffect")
    #expect(effect != .destructive)
    #expect(effect.strictness == .destructive)

  }

  @Test func ranksEffectsFromReadOnlyToDestructive() {

    #expect(CommandEffect.readOnly.strictness == .readOnly)
    #expect(CommandEffect.configuration.strictness == .change)
    #expect(CommandEffect.link.strictness == .change)
    #expect(CommandEffect.actuation.strictness == .change)
    #expect(CommandEffect.destructive.strictness == .destructive)
    #expect(CommandEffect.Strictness.readOnly < .change)
    #expect(CommandEffect.Strictness.change < .destructive)

  }

  @Test func readsTheEffectOfAKeepAwakeMessageGivenAsBytes() throws {

    let keepAwake = try #require(try Self.catalog().profile(model: "1")?.lifecycle?.fromHub?.keepAwake)

    guard case let .bytes(send) = keepAwake.send, case let .bytes(release)? = keepAwake.release else {

      Issue.record("The keep-awake messages aren't read as bytes.")

      return

    }

    #expect(send.effect == .configuration)
    #expect(send.isIdempotent == true)
    #expect(release.effect == nil)
    #expect(release.isIdempotent == nil)

  }

}
