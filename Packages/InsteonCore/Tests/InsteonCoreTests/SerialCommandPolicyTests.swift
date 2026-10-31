import Testing
import InsteonCore

/// Which serial commands a raw passthrough writes without being forced.
struct SerialCommandPolicyTests {

  @Test func recognizesSerialCommandsByTheirFirstByte() {

    #expect(SerialCommandPolicy.isSerialCommand([0x02, 0x77]))
    #expect(!SerialCommandPolicy.isSerialCommand([0x03, 0x60]))
    #expect(!SerialCommandPolicy.isSerialCommand([]))

  }

  @Test func refusesSerialCommandsThatChangeWhatTheModemKeeps() {

    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x77]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x60]) == nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x67]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x6F, 0x80]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x76]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02, 0x99]) != nil)
    #expect(SerialCommandPolicy.refusal(for: [0x02]) != nil)

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

  @Test func refusesStartAllLinkingOnlyWithTheDeleteLinkCode() {

    #expect(
      SerialCommandPolicy.refusal(for: [0x02, 0x64, 0xFF, 0x01])
        == "Start ALL-Linking (0x64) with link code 0xFF deletes the link with the next device whose SET button is pressed. Use 'insteon unlink' instead."
    )

    for linkCode: UInt8 in [0x00, 0x01, 0x03] {

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
      (Self.message(flags: 0x0F, 0x20, 0x00), .programmingLockOn),
      (Self.message(flags: 0x0F, 0x20, 0x0C), .radioOff),
      (Self.message(flags: 0x0F, 0x20, 0x0E), .powerlineOff),
      (Self.message(flags: 0x0F, 0x20, 0x19), .checksumOn),
      (Self.message(flags: 0x0F, 0x29, 0x05), .poke),
      // Send ALL-Link Command carries its cmd1 and cmd2 after the group.
      ([0x02, 0x61, 0x01, 0x20, 0x0C], .radioOff),
      // A protected message after another command in the same bytes.
      ([0x02, 0x60] + Self.message(flags: 0x0F, 0x20, 0x0E), .powerlineOff),
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

  @Test func writesARefusedCommandOnlyWhenForced() {

    let deleteLinking: [UInt8] = [0x02, 0x64, 0xFF, 0x01]
    let reason: String? = SerialCommandPolicy.refusal(for: deleteLinking)

    #expect(reason != nil)
    #expect(SerialCommandPolicy.refusal(of: deleteLinking, forcing: false) == reason.map(SendRefusal.serialCommand))
    #expect(SerialCommandPolicy.refusal(of: deleteLinking, forcing: true) == nil)
    #expect(SerialCommandPolicy.refusal(of: Self.message(flags: 0x0F, 0x11, 0xFF), forcing: false) == nil)

  }

}
