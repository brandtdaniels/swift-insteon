import Testing
import InsteonProtocol

struct ModemReplyParserTests {

  static let device = InsteonAddress(0xAA, 0xBB, 0xCC)

  static let modem = InsteonAddress(0x11, 0x22, 0x33)

  static let record = AllLinkRecord(
    flags: [.inUse, .controller, .usedBefore],
    group: 0x01,
    address: device,
    data1: 0x03,
    data2: 0x1F,
    data3: 0x01
  )

  static let replies: [(String, ModemReply)] = [
    (
      "0250" + "AABBCC" + "112233" + "2B" + "11FF",
      .messageReceived(ReceivedMessage(
        sender: device,
        destination: modem,
        flags: MessageFlags(rawValue: 0x2B),
        command: Command(command1: 0x11, command2: 0xFF)
      ))
    ),
    ("02526600", .x10Received(.unit(.a, .one))),
    ("02526280", .x10Received(.command(.a, .on))),
    (
      "0253" + "01" + "01" + "AABBCC" + "01" + "20" + "41",
      .allLinkingCompleted(AllLinkingCompleted(
        linkCode: 0x01,
        group: 0x01,
        address: device,
        category: 0x01,
        subcategory: 0x20,
        firmwareVersion: 0x41
      ))
    ),
    ("025402", .buttonEvent(0x02)),
    ("0255", .userReset),
    ("0256" + "01" + "05" + "AABBCC", .allLinkCleanupFailed(group: 0x05, address: device)),
    ("0257" + "C201AABBCC031F01", .allLinkRecord(record)),
    ("025806", .allLinkCleanupStatus(isComplete: true)),
    ("025815", .allLinkCleanupStatus(isComplete: false)),
    ("0259" + "0FF8" + "C201AABBCC031F01", .databaseRecord(address: 0x0FF8, record: record)),
    (
      "0260" + "112233" + "03" + "15" + "9B" + "06",
      .modemInfo(ModemInfo(address: modem, category: 0x03, subcategory: 0x15, firmwareVersion: 0x9B))
    ),
    ("026015", .echo(CommandEcho(number: .getModemInfo, parameters: [], isAccepted: false))),
    (
      "0273" + "40" + "05" + "00" + "06",
      .modemConfiguration(ModemConfigurationReport(configuration: .monitorMode, applicationRetries: 0x05, databaseDelta: 0x00))
    ),
    ("027315", .echo(CommandEcho(number: .getModemConfiguration, parameters: [], isAccepted: false))),
    (
      "0262" + "AABBCC" + "0F" + "11FF" + "06",
      .echo(CommandEcho(number: .sendMessage, parameters: [0xAA, 0xBB, 0xCC, 0x0F, 0x11, 0xFF], isAccepted: true))
    ),
    (
      "0262" + "AABBCC" + "0F" + "11FF" + "15",
      .echo(CommandEcho(number: .sendMessage, parameters: [0xAA, 0xBB, 0xCC, 0x0F, 0x11, 0xFF], isAccepted: false))
    ),
    (
      "026101" + "11FF" + "06",
      .echo(CommandEcho(number: .sendAllLinkCommand, parameters: [0x01, 0x11, 0xFF], isAccepted: true))
    ),
    ("02640101" + "06", .echo(CommandEcho(number: .startAllLinking, parameters: [0x01, 0x01], isAccepted: true))),
    ("0265" + "06", .echo(CommandEcho(number: .cancelAllLinking, parameters: [], isAccepted: true))),
    ("0269" + "15", .echo(CommandEcho(number: .getFirstAllLinkRecord, parameters: [], isAccepted: false))),
    (
      "026F" + "40" + "C201AABBCC031F01" + "06",
      .echo(CommandEcho(
        number: .manageAllLinkRecord,
        parameters: [0x40, 0xC2, 0x01, 0xAA, 0xBB, 0xCC, 0x03, 0x1F, 0x01],
        isAccepted: true
      ))
    ),
    ("0277" + "06", .echo(CommandEcho(number: .beep, parameters: [], isAccepted: true))),
    ("027A05" + "06", .echo(CommandEcho(number: .setApplicationRetries, parameters: [0x05], isAccepted: true)))
  ]

  @Test(arguments: replies)
  func parsesReply(_ hex: String, _ expected: ModemReply) {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes(hex)) == [expected])

  }

  @Test func parsesExtendedMessages() throws {

    var parser = ModemReplyParser()
    let userData = Array(UInt8(1)...14)

    let replies = parser.parse(bytes("0251" + "AABBCC" + "112233" + "1B" + "2E00") + userData)

    #expect(replies == [.messageReceived(ReceivedMessage(
      sender: Self.device,
      destination: Self.modem,
      flags: MessageFlags(rawValue: 0x1B),
      command: Command(command1: 0x2E, command2: 0x00),
      userData: try UserData(userData)
    ))])

  }

  @Test func parsesEchoOfExtendedMessage() throws {

    var parser = ModemReplyParser()
    let message = ExtendedMessage(
      to: Self.device,
      command: ExtendedDirectCommand.getSet,
      userData: try UserData([0x01])
    )

    let replies = parser.parse(SerialCommand.sendExtendedMessage(message).bytes + [0x06])

    #expect(replies == [.echo(CommandEcho(number: .sendMessage, parameters: message.bytes, isAccepted: true))])

  }

  // Replies captured in Insteon's own PLM test log, received back to back.
  @Test func parsesInsteonTrace() {

    var parser = ModemReplyParser()
    let pairedDevice = InsteonAddress(0x08, 0xB6, 0xEA)
    let plm = InsteonAddress(0x13, 0xD0, 0x91)

    let replies = parser.parse(bytes(
      "0260" + "13D091" + "03" + "21" + "93" + "06"
        + "0275" + "1FF8" + "06" + "0259" + "1FF8" + "E201" + "08B6EA" + "000000"
        + "0261" + "041200" + "06" + "0250" + "08B6EA" + "13D091" + "61" + "1204"
        + "025806"
        + "0274" + "06"
    ))

    #expect(replies == [
      .modemInfo(ModemInfo(address: plm, category: 0x03, subcategory: 0x21, firmwareVersion: 0x93)),
      .echo(CommandEcho(number: .readDatabase, parameters: [0x1F, 0xF8], isAccepted: true)),
      .databaseRecord(
        address: 0x1FF8,
        // E2: in use, controller and used before, plus bit 5, which real records also set.
        record: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: pairedDevice)
      ),
      .echo(CommandEcho(number: .sendAllLinkCommand, parameters: [0x04, 0x12, 0x00], isAccepted: true)),
      .messageReceived(ReceivedMessage(
        sender: pairedDevice,
        destination: plm,
        flags: MessageFlags(rawValue: 0x61),
        command: Command(command1: 0x12, command2: 0x04)
      )),
      .allLinkCleanupStatus(isComplete: true),
      .echo(CommandEcho(number: .cancelCleanup, parameters: [], isAccepted: true))
    ])

  }

  @Test func waitsForTheRestOfASplitReply() {

    var parser = ModemReplyParser()
    let frame = bytes("0250" + "AABBCC" + "112233" + "2B" + "11FF")

    #expect(parser.parse(frame.prefix(4)).isEmpty)
    #expect(parser.parse(frame.dropFirst(4).prefix(5)).isEmpty)
    #expect(parser.parse(frame.dropFirst(9)).count == 1)

  }

  @Test func parsesSeveralRepliesAtOnce() {

    var parser = ModemReplyParser()

    let replies = parser.parse(bytes("026506" + "0255" + "025806"))

    #expect(replies == [
      .echo(CommandEcho(number: .cancelAllLinking, parameters: [], isAccepted: true)),
      .userReset,
      .allLinkCleanupStatus(isComplete: true)
    ])

  }

  @Test func skipsNoiseAndUnrecognizedNumbers() {

    var parser = ModemReplyParser()

    let replies = parser.parse(bytes("FF00" + "0299" + "15" + "0255"))

    #expect(replies == [.userReset])

  }

  @Test func decodesEveryX10Code() {

    for house in X10HouseCode.allCases {

      for unit in X10UnitCode.allCases {

        let code = X10Code.unit(house, unit)
        #expect(X10Code(rawX10: code.rawX10, flag: code.flag) == code)

      }

      for command in X10Command.allCases {

        let code = X10Code.command(house, command)
        #expect(X10Code(rawX10: code.rawX10, flag: code.flag) == code)

      }

    }

  }

  @Test func reportsLinkMode() {

    let completed = AllLinkingCompleted(
      linkCode: 0xFF,
      group: 0,
      address: Self.device,
      category: 0,
      subcategory: 0,
      firmwareVersion: 0
    )

    #expect(completed.mode == .delete)

  }

  private func bytes(_ hex: String) -> [UInt8] {

    Self.bytes(hex)

  }

  private static func bytes(_ hex: String) -> [UInt8] {

    let digits = Array(hex)

    return stride(from: 0, to: digits.count, by: 2).map { UInt8(String(digits[$0..<$0 + 2]), radix: 16)! }

  }

  @Test func readsTheReasonFromANAK() {

    let nak = ReceivedMessage(
      sender: InsteonAddress(0xAA, 0xBB, 0xCC),
      destination: InsteonAddress(0x11, 0x22, 0x33),
      flags: MessageFlags(messageType: .directNegativeAcknowledgement),
      command: Command(command1: 0x11, command2: 0xFF)
    )
    let ack = ReceivedMessage(
      sender: nak.sender,
      destination: nak.destination,
      flags: MessageFlags(messageType: .directAcknowledgement),
      command: Command(command1: 0x11, command2: 0xFF)
    )

    #expect(nak.nakReason == .notLinked)
    #expect(ack.nakReason == nil)

  }

}
