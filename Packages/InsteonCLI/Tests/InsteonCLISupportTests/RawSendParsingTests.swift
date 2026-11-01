import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// The parsing of the raw passthroughs, `insteon modem send` and `insteon device ADDRESS send`:
/// their limits, options and malformed input.
struct RawSendParsingTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  // MARK: - modem send

  @Test func acceptsUpTo32BytesForAModemCommand() throws {

    let longest: [UInt8] = [0x02, 0x77] + [UInt8](repeating: 0x00, count: 30)
    let text: String = "0277" + String(repeating: "00", count: 30)

    // Its length is refused unless it's forced, but nothing in it is never written.
    #expect(try Invocation.parse(["modem", "send", text, "--force"]).subcommand == .modemSend(RawSerialRequest(bytes: longest, isForced: true)))

    let tooLong: String = text + "00"

    #expect(throws: ArgumentError.invalidValue(option: "send", value: tooLong, expected: "up to 32 bytes in hexadecimal, such as 0277 or 02 77 01")) {

      try Invocation.parse(["modem", "send", tooLong, "--force"])

    }

  }

  @Test func refusesAModemCommandThatIsntHexadecimalBytes() {

    for text in ["02ZZ", "027", "0x"] {

      #expect(throws: ArgumentError.invalidValue(option: "send", value: text, expected: "up to 32 bytes in hexadecimal, such as 0277 or 02 77 01")) {

        try Invocation.parse(["modem", "send", text])

      }

    }

  }

  @Test func asksForTheModemCommandsBytes() {

    for arguments in [["modem", "send"], ["modem", "send", "--force"], ["modem", "send", "--wait", "2"]] {

      #expect(throws: ArgumentError.missingArgument("the command's bytes in hexadecimal, such as 0277", subcommand: "modem send"), "\(arguments)") {

        try Invocation.parse(arguments)

      }

    }

  }

  @Test func refusesAModemOptionOrActionItDoesntKnow() {

    #expect(throws: ArgumentError.unknownOption("--bogus", subcommand: "modem")) {

      try Invocation.parse(["modem", "send", "0277", "--bogus"])

    }

    #expect(throws: ArgumentError.unexpectedValue(option: "--force")) {

      try Invocation.parse(["modem", "send", "0267", "--force=yes"])

    }

    #expect(throws: ArgumentError.unexpectedArgument("reset", subcommand: "modem")) {

      try Invocation.parse(["modem", "reset"])

    }

  }

  @Test func readsTheModemCommandsWait() throws {

    #expect(try Invocation.parse(["modem", "send", "0277", "--wait=5"]).subcommand == .modemSend(RawSerialRequest(bytes: [0x02, 0x77], waitSeconds: 5)))
    #expect(try Invocation.parse(["modem", "send", "0x02", "0x77"]).subcommand == .modemSend(RawSerialRequest(bytes: [0x02, 0x77])))

  }

  // MARK: - device ADDRESS send

  @Test func checksumsAnExtendedMessageUnlessAll14BytesAreGiven() throws {

    let thirteen: [String] = Array(repeating: "01", count: 13)
    let fourteen: [String] = Array(repeating: "01", count: 14)

    #expect(try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--extended"] + thirteen).subcommand
      == .device(lamp, .send(DirectMessageRequest(command1: 0x2E, command2: 0x00, userData: [UInt8](repeating: 0x01, count: 13)))))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--extended"] + fourteen).subcommand
      == .device(lamp, .send(DirectMessageRequest(command1: 0x2E, command2: 0x00, userData: [UInt8](repeating: 0x01, count: 14), hasChecksum: false))))

  }

  @Test func refusesADeviceMessageWithMoreThanTwoCommandBytes() {

    #expect(throws: ArgumentError.unexpectedArgument("01", subcommand: "device")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "19", "00", "01"])

    }

  }

  @Test func refusesADeviceCommandByteThatIsntHexadecimal() {

    #expect(throws: ArgumentError.invalidValue(option: "CMD1", value: "XY", expected: "a byte in hexadecimal, such as 0x2E")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "XY", "00"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "--extended", value: "1FF", expected: "up to 14 bytes in hexadecimal, D1 through D14")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--extended", "1FF"])

    }

  }

  @Test func refusesADeviceOptionItDoesntKnow() {

    #expect(throws: ArgumentError.unknownOption("--force", subcommand: "device")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "20", "0C", "--force"])

    }

    #expect(throws: ArgumentError.unexpectedValue(option: "--no-checksum")) {

      try Invocation.parse(["device", "1A.2B.3C", "send", "2E", "00", "--no-checksum=1"])

    }

  }

}
