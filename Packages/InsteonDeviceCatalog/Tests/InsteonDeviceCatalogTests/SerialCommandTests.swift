import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// A modem's serial commands as a command set carries them, and the effect of a serial frame
/// found by its number and bytes, read from a made-up command set.
struct SerialCommandTests {

  static let commandSet = #"""
    {
      "id": "testModem",
      "name": "Test modem",
      "description": "A made-up command set whose serial commands carry effects.",
      "serialCommands": [
        { "name": "askIdentity", "description": "Asks who the modem is.", "effect": "readOnly", "idempotent": true, "number": "0x60",
          "reply": [{ "name": "id", "description": "The modem's ID.", "bytes": [1, 2, 3] }, { "name": "kind", "description": "The kind.", "byte": 4 }] },
        { "name": "openPairing", "description": "Opens pairing.", "effect": "link", "idempotent": false, "number": "0x64",
          "fixed": [{ "position": 1, "value": "0x01" }],
          "parameters": [{ "name": "group", "description": "The group.", "byte": 2 }] },
        { "name": "closePairing", "description": "Erases a pairing.", "effect": "destructive", "idempotent": true, "number": "0x64",
          "fixed": [{ "position": 1, "value": "0xFF" }],
          "parameters": [{ "name": "group", "description": "The group.", "byte": 2 }] },
        { "name": "tuneLamp", "description": "Stores a lamp setting.", "effect": "configuration", "idempotent": true, "number": "0x68",
          "parameters": [{ "name": "level", "description": "The level.", "byte": 1 }] },
        { "name": "lookup", "description": "Looks a record up.", "effect": "readOnly", "idempotent": true, "number": "0x6F",
          "fixed": [{ "position": 1, "value": "0x00" }],
          "parameters": [{ "name": "rest", "description": "The record.", "bytes": [2, 3, 4] }] },
        { "name": "store", "description": "Stores a record.", "effect": "destructive", "idempotent": true, "number": "0x6F",
          "fixed": [{ "position": 1, "value": "0x20" }],
          "parameters": [{ "name": "rest", "description": "The record.", "bytes": [2, 3, 4] }] },
        { "name": "newer", "description": "Does something newer.", "effect": "sideEffect", "idempotent": true, "number": "0x70" },
        { "name": "unmarked", "description": "Marks nothing.", "number": "0x71" },
        { "name": "never", "description": "Is never sent.", "effect": "destructive", "idempotent": false, "guard": "never", "number": "0x72" }
      ],
      "sources": ["A"]
    }
    """#

  static func commands() throws -> CommandSet {

    let json: String = #"{ "devices": [], "commandSets": [\#(commandSet)] }"#

    return try #require(try DeviceCatalog(json: Data(json.utf8)).commandSet(id: "testModem"))

  }

  static func effect(_ number: UInt8, _ payload: [UInt8] = [], in commands: CommandSet?) -> CommandSetSafety.MessageEffect {

    CommandSetSafety.serialEffect(number: number, payload: payload, in: commands)

  }

  // MARK: - Decoding

  @Test func readsEachFieldOfASerialCommand() throws {

    let commands = try Self.commands()
    let closePairing = try #require(commands.serialCommand(named: "closePairing"))

    #expect(commands.serialCommands.count == 9)
    #expect(closePairing.summary == "Erases a pairing.")
    #expect(closePairing.number == 0x64)
    #expect(closePairing.fixedBytes == [FixedPayloadByte(position: 1, value: 0xFF)])
    #expect(closePairing.parameters.map(\.name) == ["group"])
    #expect(closePairing.effect == .destructive)
    #expect(closePairing.isIdempotent == true)
    #expect(closePairing.sendGuard == nil)

    let askIdentity = try #require(commands.serialCommand(named: "askIdentity"))

    #expect(askIdentity.reply.map(\.name) == ["id", "kind"])
    #expect(askIdentity.reply.first?.positions == [1, 2, 3])
    #expect(askIdentity.verification == .documented)
    #expect(try #require(commands.serialCommand(named: "never")).sendGuard == .never)

  }

  @Test func keepsAnEffectItDoesntKnowAndLeavesAMissingOneNil() throws {

    let commands = try Self.commands()

    #expect(try #require(commands.serialCommand(named: "newer")).effect == CommandEffect(rawValue: "sideEffect"))
    #expect(try #require(commands.serialCommand(named: "unmarked")).effect == nil)
    #expect(try #require(commands.serialCommand(named: "unmarked")).isIdempotent == nil)

  }

  @Test func decodesACommandSetWithoutSerialCommandsAsHavingNone() throws {

    let json: String = #"{ "devices": [], "commandSets": [{ "id": "plain", "name": "Plain", "description": "None.", "sources": ["A"] }] }"#
    let commands = try #require(try DeviceCatalog(json: Data(json.utf8)).commandSet(id: "plain"))

    #expect(commands.serialCommands.isEmpty)

  }

  @Test func refusesASerialCommandThatFixesAByteTwice() {

    let json: String = #"""
      { "devices": [], "commandSets": [{ "id": "bad", "name": "Bad", "description": "Fixes twice.", "sources": ["A"],
        "serialCommands": [{ "name": "twice", "description": "Twice.", "effect": "link", "idempotent": true, "number": "0x64",
          "fixed": [{ "position": 1, "value": "0x01" }, { "position": 1, "value": "0x02" }] }] }] }
      """#

    #expect(throws: DecodingError.self) { try DeviceCatalog(json: Data(json.utf8)) }

  }

  // MARK: - Effect of a frame

  @Test func findsAFrameByItsNumberAndFixedBytes() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x60, in: commands) == .described(.readOnly, isIdempotent: true))
    #expect(Self.effect(0x64, [0x01, 0x05], in: commands) == .described(.link, isIdempotent: false))
    #expect(Self.effect(0x64, [0xFF, 0x05], in: commands) == .described(.destructive, isIdempotent: true))
    #expect(Self.effect(0x68, [0x33], in: commands) == .described(.configuration, isIdempotent: true))
    #expect(Self.effect(0x6F, [0x00, 1, 2, 3], in: commands) == .described(.readOnly, isIdempotent: true))
    #expect(Self.effect(0x6F, [0x20, 1, 2, 3], in: commands) == .described(.destructive, isIdempotent: true))

  }

  @Test func leavesAFrameNoEntryMatchesUndescribed() throws {

    let commands = try Self.commands()

    // A number no entry has, and a number whose fixed byte no entry matches.
    #expect(Self.effect(0x61, in: commands) == .undescribed)
    #expect(Self.effect(0x64, [0x02, 0x05], in: commands) == .undescribed)
    #expect(Self.effect(0x6F, [0x80, 1, 2, 3], in: commands) == .undescribed)

    // A frame cut short of a fixed byte matches nothing.
    #expect(Self.effect(0x64, [], in: commands) == .undescribed)

  }

  @Test func leavesEveryFrameUndescribedWithoutACommandSet() {

    #expect(Self.effect(0x60, in: nil) == .undescribed)

  }

  @Test func readsAMissingOrUnknownEffectAsDestructiveAndAMissingIdempotentAsNot() throws {

    let commands = try Self.commands()

    #expect(Self.effect(0x70, in: commands) == .described(.destructive, isIdempotent: true))
    #expect(Self.effect(0x71, in: commands) == .described(.destructive, isIdempotent: false))

  }

  @Test func takesTheStrictestEffectOfEveryEntryAFrameMatches() throws {

    // An entry without fixed bytes matches every payload of its number, so a frame also
    // matches the stricter entry that fixes a byte.
    let json: String = #"""
      { "devices": [], "commandSets": [{ "id": "overlap", "name": "Overlap", "description": "Overlaps.", "sources": ["A"],
        "serialCommands": [
          { "name": "any", "description": "Any.", "effect": "configuration", "idempotent": true, "number": "0x64" },
          { "name": "one", "description": "One.", "effect": "destructive", "idempotent": false, "number": "0x64",
            "fixed": [{ "position": 1, "value": "0x01" }] },
          { "name": "two", "description": "Two.", "effect": "link", "idempotent": true, "number": "0x64",
            "fixed": [{ "position": 1, "value": "0x02" }] },
          { "name": "twoToo", "description": "Two too.", "effect": "actuation", "idempotent": true, "number": "0x64",
            "fixed": [{ "position": 1, "value": "0x02" }] }
        ] }] }
      """#
    let commands = try #require(try DeviceCatalog(json: Data(json.utf8)).commandSet(id: "overlap"))

    #expect(Self.effect(0x64, [0x01, 0x00], in: commands) == .described(.destructive, isIdempotent: false))
    #expect(Self.effect(0x64, [0x03, 0x00], in: commands) == .described(.configuration, isIdempotent: true))

    // Link and actuation are each as strict as the other, so neither stands for the other.
    #expect(Self.effect(0x64, [0x02, 0x00], in: commands) == .described(.destructive, isIdempotent: true))

  }

}
