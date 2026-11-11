import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// What a command does to its addressee and whether it may be sent again, as a command set's
/// entries carry them, and the effect of a message found by its bytes, read from a made-up
/// command set.
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

  static func effect(_ command1: UInt8, _ command2: UInt8, userData: [Int: UInt8]? = nil, in commands: CommandSet?) -> CommandSetSafety.MessageEffect {

    let data: UserData? = userData.map { (bytes: [Int: UInt8]) -> UserData in

      var data = UserData()

      for (position, value) in bytes {

        data[position] = value

      }

      return data

    }

    return CommandSetSafety.effect(of: Command(command1: command1, command2: command2), userData: data, in: commands)

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

  // MARK: - Standard messages

  @Test func findsAStandardCommandByItsFixedCmd2() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x15, 0x00, in: commands) == .described(.actuation, isIdempotent: false))
    #expect(Self.effect(0x19, 0x00, in: commands) == .described(.readOnly, isIdempotent: true))
    // Another cmd2 is another message, which nothing describes.
    #expect(Self.effect(0x19, 0x01, in: commands) == .undescribed)

  }

  @Test func findsAStandardCommandByAnyCmd2ItsParameterAllows() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x11, 0x00, in: commands) == .described(.actuation, isIdempotent: true))
    #expect(Self.effect(0x11, 0xFF, in: commands) == .described(.actuation, isIdempotent: true))
    // An enumeration allows only the values it names.
    #expect(Self.effect(0x30, 0x02, in: commands) == .described(.configuration, isIdempotent: true))
    #expect(Self.effect(0x30, 0x03, in: commands) == .undescribed)

  }

  @Test func findsAFlagCommandAndAnOperatingFlagsOnAndOffBySetOperatingFlags() throws {

    let commands = try Self.commands()

    // The flag's off, which only the flag names: configuration, and idempotent.
    #expect(Self.effect(0x20, 0x41, in: commands) == .described(.configuration, isIdempotent: true))
    // The same cmd2 sent as an extended message, with any user data, as for i2CS.
    #expect(Self.effect(0x20, 0x41, userData: [14: 0x9F], in: commands) == .described(.configuration, isIdempotent: true))
    // A cmd2 nothing names.
    #expect(Self.effect(0x20, 0x48, in: commands) == .undescribed)

  }

  // MARK: - Failing closed

  @Test func readsAnEntryWithoutAnEffectOrIdempotentAsDestructiveAndNotIdempotent() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x32, 0x02, in: commands) == .described(.destructive, isIdempotent: false))
    #expect(Self.effect(0x20, 0x44, in: commands) == .described(.destructive, isIdempotent: false))

  }

  @Test func readsAnEffectItDoesntKnowAsDestructive() throws {

    #expect(Self.effect(0x31, 0x01, in: try Self.commands()) == .described(.destructive, isIdempotent: true))

  }

  @Test func takesTheStrictestEffectOfTheEntriesAMessageMatches() throws {

    // The flag command is configuration and the standard command with its bytes destructive.
    #expect(Self.effect(0x20, 0x42, in: try Self.commands()) == .described(.destructive, isIdempotent: true))

  }

  @Test func readsTwoDifferentEffectsOfTheSameRankAsDestructive() throws {

    // Neither link nor actuation covers the other, so no consent for one stands for both.
    #expect(Self.effect(0x33, 0x03, in: try Self.commands()) == .described(.destructive, isIdempotent: true))

  }

  @Test func isIdempotentOnlyIfEveryEntryItMatchesIs() throws {

    // The flag's on is idempotent and the flag command with its cmd2 isn't.
    #expect(Self.effect(0x20, 0x40, in: try Self.commands()) == .described(.configuration, isIdempotent: false))

  }

  @Test func describesNothingForADeviceWithoutACommandSet() {

    #expect(Self.effect(0x19, 0x00, in: nil) == .undescribed)
    #expect(Self.effect(0x20, 0x41, userData: [:], in: nil) == .undescribed)

  }

  // MARK: - Extended messages

  @Test func findsAnExtendedCommandOnlyWhenEveryByteItDoesntFillIsZero() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x2E, 0x02, userData: [:], in: commands) == .described(.readOnly, isIdempotent: true))
    // The read fixes no byte, but a nonzero byte isn't the read.
    #expect(Self.effect(0x2E, 0x02, userData: [5: 0x01], in: commands) == .undescribed)
    // The write's bytes: its fixed D2, its parameter in D3 and its checksum in D14. The read
    // expects 0x00 in each, so only the write matches.
    #expect(Self.effect(0x2E, 0x02, userData: [2: 0x02, 3: 0x7F, 14: 0x4D], in: commands) == .described(.configuration, isIdempotent: true))
    // A nonzero byte the write doesn't fill matches neither.
    #expect(Self.effect(0x2E, 0x02, userData: [2: 0x02, 3: 0x7F, 9: 0x01], in: commands) == .undescribed)
    // A fixed byte with another value matches neither.
    #expect(Self.effect(0x2E, 0x02, userData: [2: 0x03], in: commands) == .undescribed)

  }

  @Test func letsAPerButtonD1AndTheIntegrityBytesHoldAnyValue() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x2F, 0x00, userData: [1: 0x03, 2: 0x05, 4: 0x10, 13: 0xAB, 14: 0xCD], in: commands) == .described(.configuration, isIdempotent: true))
    #expect(Self.effect(0x2F, 0x00, userData: [1: 0x03, 2: 0x05, 4: 0x10, 12: 0x01], in: commands) == .undescribed)

  }

  @Test func findsAnExtendedSettingsWriteByItsSelector() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x2E, 0x00, userData: [1: 0x01, 2: 0x06, 3: 0x20, 14: 0x8B], in: commands) == .described(.configuration, isIdempotent: true))
    // A selector the command set doesn't list, and the extended Get, which no entry describes.
    #expect(Self.effect(0x2E, 0x00, userData: [1: 0x01, 2: 0x07, 3: 0x20], in: commands) == .undescribed)
    #expect(Self.effect(0x2E, 0x00, userData: [1: 0x01], in: commands) == .undescribed)

  }

  @Test func findsAStandardCommandSentInItsExtendedWhenForm() throws {

    let commands = try Self.commands()

    // cmd1 and cmd2 again in D1 and D2, the rest 0x00 apart from the integrity bytes.
    #expect(Self.effect(0x11, 0x80, userData: [1: 0x11, 2: 0x80], in: commands) == .described(.actuation, isIdempotent: true))
    #expect(Self.effect(0x11, 0x80, userData: [1: 0x11, 2: 0x80, 13: 0x12, 14: 0x34], in: commands) == .described(.actuation, isIdempotent: true))
    // D2 that isn't cmd2, or another nonzero byte, isn't the form.
    #expect(Self.effect(0x11, 0x80, userData: [1: 0x11, 2: 0x81], in: commands) == .undescribed)
    #expect(Self.effect(0x11, 0x80, userData: [1: 0x11, 2: 0x80, 5: 0x01], in: commands) == .undescribed)
    // A standard command sent as an extended message in no other form is undescribed.
    #expect(Self.effect(0x15, 0x00, userData: [:], in: commands) == .undescribed)

  }

}
