import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// Which serial commands a raw passthrough writes without being forced.
struct SerialCommandPolicyTests {

  @Test func recognizesSerialCommandsByTheirFirstByte() {

    #expect(SerialCommandPolicy.isSerialCommand([0x02, 0x77]))
    #expect(!SerialCommandPolicy.isSerialCommand([0x03, 0x60]))
    #expect(!SerialCommandPolicy.isSerialCommand([]))

  }

  @Test func refusesAnUnknownCommandNumberAndATruncatedCommand() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x99]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02]) != nil)

  }

  @Test func leavesWhatACommandDoesToTheModemsCommandSet() {

    // The reasons a command changes or erases what the modem keeps come from the modem's
    // command set, so the framing check passes each of them.
    for number: UInt8 in [0x66, 0x67, 0x6B, 0x72, 0x76, 0x7D, 0x82] {

      let bytes: [UInt8] = [0x02, number] + [UInt8](repeating: 0x00, count: (SerialCommandNumber(rawValue: number)?.commandLength ?? 2) - 2)

      #expect(SerialCommandPolicy.refusal(for: bytes) == nil, "\(number)")

    }

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x6F, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) == nil)

  }

  @Test func namesAnUnknownCommandNumberInHexadecimal() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x09]) == "0x09 isn't a serial command the package knows, so the modem's answer can't be read.")

  }

  // MARK: - Lengths

  /// Send Insteon Standard or Extended Message (`0x62`) to `1A.2B.3C` with message flags, a
  /// command and any user data.
  static func message(flags: UInt8, _ command1: UInt8, _ command2: UInt8, data: [UInt8] = []) -> [UInt8] {

    [0x02, 0x62, 0x1A, 0x2B, 0x3C, flags, command1, command2] + data

  }

  /// An extended message, flags `0x1F`, with D1 through D14 given or zero.
  static func extended(_ command1: UInt8, _ command2: UInt8, d2: UInt8 = 0x00) -> [UInt8] {

    var data = [UInt8](repeating: 0x00, count: 14)
    data[1] = d2

    return message(flags: 0x1F, command1, command2, data: data)

  }

  @Test func refusesASendMessageOfTheWrongLengthForItsFlags() {

    let standard: [UInt8] = Self.message(flags: 0x0F, 0x11, 0xFF)

    #expect(SerialCommandPolicy.refusal(for: standard) == nil)
    #expect(SerialCommandPolicy.refusal(for: Self.extended(0x11, 0xFF)) == nil)

    #expect(
      SerialCommandPolicy.refusal(for: Array(standard.dropLast()))
        == "Serial command 0x62 with a standard message has 8 bytes, counting 02, not 7."
    )
    #expect(
      SerialCommandPolicy.refusal(for: standard + [UInt8](repeating: 0x00, count: 14))
        == "Serial command 0x62 with a standard message has 8 bytes, counting 02, not 22."
    )
    #expect(
      SerialCommandPolicy.refusal(for: Self.message(flags: 0x1F, 0x11, 0xFF))
        == "Serial command 0x62 with an extended message (flags bit 4 set) has 22 bytes, counting 02, not 8."
    )
    #expect(
      SerialCommandPolicy.refusal(for: [0x02, 0x62, 0x1A, 0x2B, 0x3C])
        == "Serial command 0x62 needs a device's address and message flags after its number."
    )

  }

  @Test func acceptsABeepOfTwoOrThreeBytes() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x77]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x77, 0x01]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x77, 0x01, 0x00]) == "Serial command 0x77 has 2 or 3 bytes, counting 02, not 4.")

  }

  @Test func refusesACommandOfAFixedLengthWithAnotherLength() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x60, 0x00]) == "Serial command 0x60 has 2 bytes, counting 02, not 3.")
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x64, 0x01]) == "Serial command 0x64 has 4 bytes, counting 02, not 3.")
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x64, 0x01, 0x00, 0x00]) == "Serial command 0x64 has 4 bytes, counting 02, not 5.")
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x64, 0x01, 0x00]) == nil)

  }

  // MARK: - Contents

  @Test func leavesTheLinkCodeOfStartAllLinkingToTheModemsCommandSet() {

    for linkCode: UInt8 in [0x00, 0x01, 0x03, 0xFF] {

      #expect(SerialCommandPolicy.refusal(for: [0x02, 0x64, linkCode, 0x01]) == nil, "link code \(linkCode)")

    }

  }

  @Test func refusesAMessageThatWritesToADevice() {

    let databaseReason = "Read/Write ALL-Link Database (0x2F) can change a device's ALL-Link database. Use 'insteon device ADDRESS send' for it."
    let flagsReason = "Set Operating Flags (0x20) changes a device's settings. Use 'insteon device ADDRESS set' for it."
    let settingsReason = "Extended Set/Get (0x2E) with D2 other than 0x00 changes a device's settings. Use 'insteon device ADDRESS set' for it."

    #expect(SerialCommandPolicy.refusal(for: Self.message(flags: 0x0F, 0x2F, 0x00)) == databaseReason)
    #expect(SerialCommandPolicy.refusal(for: Self.extended(0x2F, 0x00)) == databaseReason)
    #expect(SerialCommandPolicy.refusal(for: Self.message(flags: 0x0F, 0x20, 0x04)) == flagsReason)
    #expect(SerialCommandPolicy.refusal(for: Self.extended(0x2E, 0x00, d2: 0x06)) == settingsReason)

  }

  @Test func sendsAnExtendedGetAndAStandardExtendedSetGetCommand() {

    // D2 0x00 asks for the settings rather than writing them.
    #expect(SerialCommandPolicy.refusal(for: Self.extended(0x2E, 0x00)) == nil)

    // A standard message can't carry D2, so it writes nothing.
    #expect(SerialCommandPolicy.refusal(for: Self.message(flags: 0x0F, 0x2E, 0x00)) == nil)

  }

  // MARK: - Never written

  @Test func neverWritesAProtectedCommandEvenWhenForced() {

    let cases: [([UInt8], ProtectedCommand)] = [
      (Self.message(flags: 0x0F, 0x20, 0x00), .setOperatingFlags0x00),
      (Self.message(flags: 0x0F, 0x20, 0x0C), .setOperatingFlags0x0C),
      (Self.message(flags: 0x0F, 0x20, 0x0E), .setOperatingFlags0x0E),
      (Self.message(flags: 0x0F, 0x20, 0x19), .setOperatingFlags0x19),
      (Self.message(flags: 0x0F, 0x29, 0x05), .poke),
      // Send ALL-Link Command carries its cmd1 and cmd2 after the group.
      ([0x02, 0x61, 0x01, 0x20, 0x0C], .setOperatingFlags0x0C),
      // A protected message after another command in the same bytes.
      ([0x02, 0x60] + Self.message(flags: 0x0F, 0x20, 0x0E), .setOperatingFlags0x0E),
    ]

    for (bytes, protected) in cases {

      #expect(SerialCommandPolicy.neverWritten(bytes) == .protected(protected), "\(bytes)")
      #expect(SerialCommandPolicy.refusal(of: bytes, forcing: true) == .protected(protected), "\(bytes)")

    }

  }

  @Test func neverWritesBytesThatArentASerialCommandOrCutAMessageShort() {

    #expect(SerialCommandPolicy.refusal(of: [0x03, 0x60], forcing: true) == .notSerialCommand)
    #expect(SerialCommandPolicy.refusal(of: [], forcing: true) == .notSerialCommand)
    #expect(SerialCommandPolicy.refusal(of: [0x02, 0x62, 0x1A, 0x2B, 0x3C, 0x0F, 0x20], forcing: true) == .incompleteMessage)
    #expect(SerialCommandPolicy.refusal(of: [0x02, 0x61, 0x01, 0x20], forcing: true) == .incompleteMessage)

  }

  @Test func writesAnUnframedCommandOnlyWhenForced() {

    let unknown: [UInt8] = [0x02, 0x09]
    let reason: String? = SerialCommandPolicy.refusal(for: unknown)

    #expect(reason != nil)
    #expect(SerialCommandPolicy.refusal(of: unknown, forcing: false) == reason.map(SendRefusal.serialCommand))
    #expect(SerialCommandPolicy.refusal(of: unknown, forcing: true) == nil)
    #expect(SerialCommandPolicy.refusal(of: Self.message(flags: 0x0F, 0x11, 0xFF), forcing: false) == nil)
    #expect(SerialCommandPolicy.refusal(of: [0x02, 0x67], forcing: false) == nil)

  }

  // MARK: - Decisions from the modem's command set

  /// A made-up modem whose serial commands carry an effect each, told apart by their fixed
  /// bytes where one number does several things.
  static let modemCommands: CommandSet = {

    let json = #"""
      {
        "devices": [],
        "commandSets": [{
          "id": "exampleModem",
          "name": "Example modem",
          "description": "Serial commands that each do something different.",
          "serialCommands": [
            { "name": "readIdentity", "description": "Reads.", "effect": "readOnly", "idempotent": true, "number": "0x60" },
            { "name": "openPairing", "description": "Opens.", "effect": "link", "idempotent": false, "number": "0x64",
              "fixed": [{ "position": 1, "value": "0x01" }], "parameters": [{ "name": "group", "description": "Group.", "byte": 2 }] },
            { "name": "erasePairing", "description": "Erases.", "effect": "destructive", "idempotent": true, "number": "0x64",
              "fixed": [{ "position": 1, "value": "0xFF" }], "parameters": [{ "name": "group", "description": "Group.", "byte": 2 }] },
            { "name": "blink", "description": "Blinks.", "effect": "actuation", "idempotent": true, "number": "0x6D" },
            { "name": "tuneAck", "description": "Tunes.", "effect": "configuration", "idempotent": true, "number": "0x68",
              "parameters": [{ "name": "value", "description": "Value.", "byte": 1 }] },
            { "name": "wipe", "description": "Wipes.", "effect": "destructive", "idempotent": true, "number": "0x67" },
            { "name": "findRecord", "description": "Finds.", "effect": "readOnly", "idempotent": true, "number": "0x6F",
              "fixed": [{ "position": 1, "value": "0x00" }], "parameters": [{ "name": "record", "description": "Record.", "bytes": [2, 3, 4] }] },
            { "name": "mislabeledDelete", "description": "Deletes.", "effect": "readOnly", "idempotent": true, "number": "0x6F",
              "fixed": [{ "position": 1, "value": "0x80" }], "parameters": [{ "name": "record", "description": "Record.", "bytes": [2, 3, 4] }] },
            { "name": "unmarked", "description": "Marks nothing.", "number": "0x6B", "parameters": [{ "name": "value", "description": "Value.", "byte": 1 }] },
            { "name": "alsoTune", "description": "Tunes too.", "effect": "configuration", "idempotent": true, "number": "0x6C" },
            { "name": "neverSend", "description": "Is never sent.", "effect": "destructive", "idempotent": false, "guard": "never", "number": "0x6E" },
            { "name": "alsoLink", "description": "Links too.", "effect": "link", "idempotent": true, "number": "0x6C" }
          ],
          "sources": ["A"]
        }]
      }
      """#

    return try! DeviceCatalog(json: Data(json.utf8)).commandSet(id: "exampleModem")!

  }()

  static func decision(_ bytes: [UInt8], commands: CommandSet? = modemCommands, forcing: Bool = false) -> SendDecision {

    SerialCommandPolicy.decision(of: bytes, commands: commands, forcing: forcing)

  }

  @Test func sendsWhatTheCommandSetCallsReadOnlyLinkOrActuation() {

    #expect(Self.decision([0x02, 0x60]) == .transmit)
    #expect(Self.decision([0x02, 0x64, 0x01, 0x01]) == .transmit)
    #expect(Self.decision([0x02, 0x6D]) == .transmit)
    #expect(Self.decision([0x02, 0x6F, 0x00, 0xE2, 0x01, 0x1A, 0x2B, 0x3C, 0x00, 0x00, 0x00]) == .transmit)

  }

  @Test func asksForConsentToConfigureOrDestroyUnlessForced() {

    #expect(Self.decision([0x02, 0x68, 0x01]) == .needsConsent(.configuration))
    #expect(Self.decision([0x02, 0x67]) == .needsConsent(.destructive))
    #expect(Self.decision([0x02, 0x64, 0xFF, 0x01]) == .needsConsent(.destructive))

    #expect(Self.decision([0x02, 0x68, 0x01], forcing: true) == .transmit)
    #expect(Self.decision([0x02, 0x67], forcing: true) == .transmit)
    #expect(Self.decision([0x02, 0x64, 0xFF, 0x01], forcing: true) == .transmit)

  }

  @Test func readsAnEffectTheCommandSetLeavesOutOrDoesntKnowAsDestructive() {

    #expect(Self.decision([0x02, 0x6B, 0x00]) == .needsConsent(.destructive))
    #expect(Self.decision([0x02, 0x6B, 0x00], forcing: true) == .transmit)

  }

  @Test func takesTheStrictestOfTheEntriesAFrameMatches() {

    // Configuration and link rank alike, so neither stands for the other.
    #expect(Self.decision([0x02, 0x6C]) == .needsConsent(.destructive))

  }

  @Test func needsConsentForACommandNoEntryDescribes() {

    // Radio is a command number the package knows and the command set doesn't describe.
    #expect(Self.decision([0x02, 0x7D, 0x00]) == .needsConsent(nil))
    #expect(Self.decision([0x02, 0x7D, 0x00], forcing: true) == .transmit)

    // So is a number the package doesn't know, which also can't be framed.
    #expect(Self.decision([0x02, 0x09]) == .refuse(.serialCommand("0x09 isn't a serial command the package knows, so the modem's answer can't be read.")))
    #expect(Self.decision([0x02, 0x09], forcing: true) == .transmit)

  }

  @Test func needsConsentForEveryCommandWhenTheModemHasNoCommandSetExceptWhatCoreBuilds() {

    // Described by nothing, so a command needs --force unless a core flow builds it.
    #expect(Self.decision([0x02, 0x67], commands: nil) == .needsConsent(nil))
    #expect(Self.decision([0x02, 0x68, 0x01], commands: nil) == .needsConsent(nil))
    #expect(Self.decision([0x02, 0x6D], commands: nil) == .needsConsent(nil))
    #expect(Self.decision([0x02, 0x67], commands: nil, forcing: true) == .transmit)

    #expect(Self.decision([0x02, 0x60], commands: nil) == .transmit)
    #expect(Self.decision([0x02, 0x65], commands: nil) == .transmit)
    #expect(Self.decision([0x02, 0x69], commands: nil) == .transmit)
    #expect(Self.decision([0x02, 0x6A], commands: nil) == .transmit)
    #expect(Self.decision([0x02, 0x77], commands: nil) == .transmit)
    #expect(Self.decision([0x02, 0x64, 0x01, 0x01], commands: nil) == .transmit)
    #expect(Self.decision([0x02, 0x64, 0xFF, 0x01], commands: nil) == .needsConsent(.destructive))

  }

  @Test func letsTheStricterOfTheFlowsDeclarationAndTheCommandSetDecide() {

    // The command set marks Manage ALL-Link Record's delete code read-only; the removal flow
    // declares it destructive.
    let delete: [UInt8] = [0x02, 0x6F, 0x80, 0xE2, 0x01, 0x1A, 0x2B, 0x3C, 0x00, 0x00, 0x00]

    #expect(Self.decision(delete) == .needsConsent(.destructive))
    #expect(Self.decision(delete, forcing: true) == .transmit)

  }

  @Test func sendsAMessageCarriedToADeviceWithoutForcingWhateverTheModemIs() {

    let lightOn: [UInt8] = Self.message(flags: 0x0F, 0x11, 0xFF)

    #expect(Self.decision(lightOn) == .transmit)
    #expect(Self.decision(lightOn, commands: nil) == .transmit)
    #expect(Self.decision([0x02, 0x61, 0x01, 0x11, 0xFF], commands: nil) == .transmit)

  }

  @Test func keepsTheFloorAndTheDeviceWritesOutOfReachOfConsent() {

    #expect(Self.decision(Self.message(flags: 0x0F, 0x29, 0x05), forcing: true) == .refuse(.protected(.poke)))
    #expect(Self.decision([0x02, 0x61, 0x01, 0x20, 0x0C], forcing: true) == .refuse(.protected(.setOperatingFlags0x0C)))
    #expect(Self.decision(Self.message(flags: 0x0F, 0x20, 0x0C), commands: nil, forcing: true) == .refuse(.protected(.setOperatingFlags0x0C)))

    // A write to a device is routed to `device send` unless forced.
    let write: [UInt8] = Self.message(flags: 0x0F, 0x20, 0x04)

    guard case .refuse(.serialCommand)? = Optional(Self.decision(write)) else {

      Issue.record("Expected a serialCommand refusal.")

      return

    }

    #expect(Self.decision(write, forcing: true) == .transmit)

  }

  @Test func neverWritesACommandTheCommandSetNeverSendsWhateverIsGranted() {

    #expect(Self.decision([0x02, 0x6E]) == .refuse(.neverSentToModem))
    #expect(Self.decision([0x02, 0x6E], forcing: true) == .refuse(.neverSentToModem))
    #expect(SendRefusal.neverSentToModem.canBeForced == false)

  }

  @Test func grantsReadOnlyLinkAndActuationUnforcedAndEverythingForced() {

    #expect(SerialCommandPolicy.consent(forcing: false) == SendConsent(effects: [.link, .actuation]))
    #expect(SerialCommandPolicy.consent(forcing: true) == SendConsent(effects: [.configuration, .link, .actuation, .destructive], allowsUndescribed: true))

  }

}
