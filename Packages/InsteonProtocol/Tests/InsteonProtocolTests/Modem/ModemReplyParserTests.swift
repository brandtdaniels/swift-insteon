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
    // As a responder, the modem reports no identity for the other device.
    (
      "0253" + "00" + "01" + "AABBCC" + "01" + "20" + "41",
      .allLinkingCompleted(AllLinkingCompleted(
        linkCode: 0x00,
        group: 0x01,
        address: device,
        category: nil,
        subcategory: nil,
        firmwareVersion: nil
      ))
    ),
    // Newer devices report 0xFF in place of a firmware version.
    (
      "0253" + "01" + "01" + "AABBCC" + "01" + "20" + "FF",
      .allLinkingCompleted(AllLinkingCompleted(
        linkCode: 0x01,
        group: 0x01,
        address: device,
        category: 0x01,
        subcategory: 0x20,
        firmwareVersion: nil
      ))
    ),
    ("025402", .buttonEvent(ModemButtonEvent(button: .set, action: .tapped))),
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
    (
      "0273" + "40" + "05" + "00" + "06",
      .modemConfiguration(ModemConfigurationReport(configuration: .monitorMode, applicationRetries: 0x05, databaseDelta: 0x00))
    ),
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
    (
      "0279" + "FF1F03" + "06",
      .echo(CommandEcho(number: .setResponderLinkData, parameters: [0xFF, 0x1F, 0x03], isAccepted: true))
    ),
    (
      "0279" + "FF1F03" + "15",
      .echo(CommandEcho(number: .setResponderLinkData, parameters: [0xFF, 0x1F, 0x03], isAccepted: false))
    ),
    ("027A05" + "06", .echo(CommandEcho(number: .setApplicationRetries, parameters: [0x05], isAccepted: true))),
    ("027D80" + "15", .echo(CommandEcho(number: .setRadio, parameters: [0x80], isAccepted: false))),
    ("027D01" + "06", .echo(CommandEcho(number: .setRadio, parameters: [0x01], isAccepted: true))),
    // Later firmware's beep echoes its parameter byte.
    ("0277" + "01" + "15", .echo(CommandEcho(number: .beep, parameters: [0x01], isAccepted: false))),
    // Captured examples.
    ("0281" + "08" + "06", .echo(CommandEcho(number: .readDiagnostics, parameters: [0x08], isAccepted: true))),
    (
      "025A" + "27C77C" + "10A30F" + "E0" + "02" + "000D" + "06",
      .diagnosticRecord(ModemDiagnosticRecord(
        sender: InsteonAddress(0x27, 0xC7, 0x7C),
        recipient: InsteonAddress(0x10, 0xA3, 0x0F),
        flags: MessageFlags(rawValue: 0xE0),
        count: 2,
        totalCount: 0x000D
      ))
    ),
    (
      "0282" + "08B6EA" + "00" + "07" + "10A30F" + "FF1C00" + "06",
      .echo(CommandEcho(
        number: .manageDeviceRecord,
        parameters: [0x08, 0xB6, 0xEA, 0x00, 0x07, 0x10, 0xA3, 0x0F, 0xFF, 0x1C, 0x00],
        isAccepted: true
      ))
    ),
    (
      "025B" + "0FE7" + "A2" + "07" + "10A30F" + "071C00" + "06",
      .deviceRecordFound(
        address: 0x0FE7,
        record: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x07, address: InsteonAddress(0x10, 0xA3, 0x0F), data1: 0x07, data2: 0x1C)
      )
    ),
    (
      "027E" + "87" + "81" + "00" + "02" + "00" + "00" + "06",
      .radioStatus(ModemRadioStatus(frequencyCode: 0x87, radioFlags: 0x81, lightFlags: 0x00, hardwareVersion: 0x02))
    )
  ]

  @Test(arguments: replies)
  func parsesReply(_ hex: String, _ expected: ModemReply) {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes(hex)) == [expected])

  }

  @Test(arguments: replies)
  func parsesReplySplitAtEveryByte(_ hex: String, _ expected: ModemReply) {

    let frame = bytes(hex)

    for split in 1..<frame.count {

      var parser = ModemReplyParser()
      let replies = parser.parse(frame.prefix(split)) + parser.parse(frame.dropFirst(split))

      #expect(replies == [expected], "split at byte \(split)")

    }

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
      command: ExtendedDirectCommand.getSet(),
      userData: try UserData([0x01])
    )

    let replies = parser.parse(SerialCommand.sendExtendedMessage(message).bytes + [0x06])

    #expect(replies == [.echo(CommandEcho(number: .sendMessage, parameters: message.bytes, isAccepted: true))])

  }

  // Captured replies, received back to back.
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

  // Captured: the responder link data set with 0x79 shows up in the record
  // that the next ALL-Linking creates. Before linking, the log puts the device into linking mode
  // for group 2 with an extended message, so the link is in group 2 although the modem was
  // asked for group 1.
  @Test func parsesResponderLinkDataTrace() {

    var parser = ModemReplyParser()
    let device = InsteonAddress(0x10, 0xA3, 0x0F)

    let replies = parser.parse(bytes(
      "0279" + "FF1F03" + "06"
        + "0264" + "0001" + "06" + "0253" + "00" + "02" + "10A30F" + "FF1F03"
        + "026F" + "00" + "00" + "02" + "10A30F" + "FF1F03" + "06" + "0257" + "A202" + "10A30F" + "FF1F03"
    ))

    #expect(replies == [
      .echo(CommandEcho(number: .setResponderLinkData, parameters: [0xFF, 0x1F, 0x03], isAccepted: true)),
      .echo(CommandEcho(number: .startAllLinking, parameters: [0x00, 0x01], isAccepted: true)),
      .allLinkingCompleted(AllLinkingCompleted(
        linkCode: 0x00,
        group: 0x02,
        address: device,
        // The modem became the responder, so the identity bytes aren't the device's: they're
        // the link data set with 0x79.
        category: nil,
        subcategory: nil,
        firmwareVersion: nil
      )),
      .echo(CommandEcho(
        number: .manageAllLinkRecord,
        parameters: [0x00, 0x00, 0x02, 0x10, 0xA3, 0x0F, 0xFF, 0x1F, 0x03],
        isAccepted: true
      )),
      .allLinkRecord(AllLinkRecord(
        flags: AllLinkRecordFlags(rawValue: 0xA2),
        group: 0x02,
        address: device,
        data1: 0xFF,
        data2: 0x1F,
        data3: 0x03
      ))
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

  // A diagnostic record's addresses can hold a start byte followed by a reply's number.
  @Test func readsADiagnosticRecordWhoseBytesLookLikeAReply() {

    var parser = ModemReplyParser()

    let replies = parser.parse(bytes("025A" + "AAAA02" + "025012" + "03" + "01" + "0001" + "06" + "0255"))

    #expect(replies == [
      .diagnosticRecord(ModemDiagnosticRecord(
        sender: InsteonAddress(0xAA, 0xAA, 0x02),
        recipient: InsteonAddress(0x02, 0x50, 0x12),
        flags: MessageFlags(rawValue: 0x03),
        count: 1,
        totalCount: 1
      )),
      .userReset,
    ])

  }

  // Without an ACK at the end, a 0x5A start isn't a report, so the parser looks for the next
  // start byte.
  @Test func skipsAReportThatDoesntEndInAnAnswer() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("025A" + "0000000000000000000000" + "0255")) == [.userReset])

  }

  @Test func reportsARejectedRadioStatusRequestOnceTheNextReplyArrives() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("027E" + "15" + Self.replies[0].0)) == [
      .echo(CommandEcho(number: .readRadioStatus, parameters: [], isAccepted: false)),
      Self.replies[0].1,
    ])

  }

  @Test func readsWhetherTheRadioIsOn() {

    #expect(!ModemRadioStatus(frequencyCode: 0x87, radioFlags: 0x81, lightFlags: 0, hardwareVersion: 2).isRadioEnabled)
    #expect(ModemRadioStatus(frequencyCode: 0x87, radioFlags: 0x80, lightFlags: 0, hardwareVersion: 2).isRadioEnabled)
    #expect(ModemDiagnosticRecord(sender: InsteonAddress(0, 0, 0), recipient: InsteonAddress(0, 0, 0), flags: MessageFlags(rawValue: 0), count: 0, totalCount: 0x0D).isEmpty)

  }

  @Test func reportsALoneNegativeAcknowledgment() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("15" + "0255")) == [.negativeAcknowledgment, .userReset])

  }

  @Test func ignoresANegativeAcknowledgmentAmongSkippedBytes() {

    var parser = ModemReplyParser()

    // Neither frame is a reply: 0x15 isn't a reply number, and the 0x61 echo doesn't end in an
    // ACK or NAK. Their bytes are skipped, NAK bytes included.
    #expect(parser.parse(bytes("0215" + "0261" + "153344" + "55" + "0255")) == [.userReset])

  }

  // Skipping lasts until the next start byte, however the bytes arrive.
  @Test func ignoresANegativeAcknowledgmentAmongSkippedBytesThatArriveLater() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("0299")).isEmpty)
    #expect(parser.parse(bytes("15")).isEmpty)
    #expect(parser.parse(bytes("AA")).isEmpty)
    #expect(parser.parse(bytes("15" + "0255" + "15")) == [.userReset, .negativeAcknowledgment])

  }

  // A stray byte starts skipping, which ends at the next start byte or once a wait ends with
  // nothing pending, so a later NAK isn't skipped for good.
  @Test func stopsSkippingOnceAWaitEnds() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("AA")).isEmpty)
    #expect(parser.parse(bytes("15")).isEmpty)

    let discarded: Bool = parser.discardStalledFrame()

    #expect(!discarded)
    #expect(parser.parse(bytes("15")) == [.negativeAcknowledgment])

  }

  @Test func finishesARejectedInfoRequestWhenNoMoreBytesCome() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("026015")).isEmpty)
    #expect(parser.finishPendingReply() == [.echo(CommandEcho(number: .getModemInfo, parameters: [], isAccepted: false))])
    #expect(parser.parse(bytes("026D06")) == [.echo(CommandEcho(number: .ledOn, parameters: [], isAccepted: true))])

  }

  // The frame start after the NAK settles it as a rejection at once, without waiting for the
  // answer's timeout, and the frame after it is read as usual.
  @Test func readsARejectedConfigurationRequestAndTheRepliesAfterIt() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("027315" + "0255")) == [
      .echo(CommandEcho(number: .getModemConfiguration, parameters: [], isAccepted: false)),
      .userReset
    ])
    #expect(parser.finishPendingReply().isEmpty)

  }

  @Test func keepsPendingBytesThatArentARejectedRequest() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("0250AABB")).isEmpty)
    #expect(parser.finishPendingReply().isEmpty)
    #expect(parser.parse(bytes("CC" + "112233" + "2B" + "11FF")).count == 1)

  }

  // A frame that lost bytes from its middle would take the next frame's bytes as its own, so
  // once nothing has arrived for a while its bytes are discarded whole, never read as frames.
  @Test func discardsAFrameThatStalled() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("0250AABB" + "0255")).isEmpty)
    #expect(parser.finishPendingReply().isEmpty)
    let discarded: Bool = parser.discardStalledFrame()
    #expect(discarded)
    #expect(parser.parse(bytes("0255")) == [.userReset])
    let discarded2: Bool = parser.discardStalledFrame()
    #expect(!discarded2)

  }

  // An extended message arriving a byte at a time, with every timeout along the way, whose
  // user data looks like a standard message: only the extended message is reported.
  @Test func neverReadsTheDataOfASlowMessageAsAReply() throws {

    var parser = ModemReplyParser()
    let userData: [UInt8] = bytes("0250" + "AABBCC" + "112233" + "2B" + "11FF" + "060606")
    let frame: [UInt8] = bytes("0251" + "AABBCC" + "112233" + "1B" + "2E00") + userData
    var replies: [ModemReply] = []

    for byte in frame {

      replies += parser.parse([byte])
      replies += parser.finishPendingReply()

    }

    #expect(replies == [.messageReceived(ReceivedMessage(
      sender: Self.device,
      destination: Self.modem,
      flags: MessageFlags(rawValue: 0x1B),
      command: Command(command1: 0x2E, command2: 0x00),
      userData: try UserData(userData)
    ))])

  }

  @Test func keepsNegativeAcknowledgmentInsideAnEcho() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("026D15")) == [.echo(CommandEcho(number: .ledOn, parameters: [], isAccepted: false))])

  }

  // The counter-case for ending a NAK at the next frame: `15 AA` isn't a NAK followed by a
  // frame, so the whole reply is read as the modem's information.
  @Test func parsesModemInfoForAnAddressStartingWithNAK() {

    var parser = ModemReplyParser()

    let replies = parser.parse(bytes("0260" + "15AABB" + "03" + "21" + "93" + "06"))

    #expect(replies == [
      .modemInfo(ModemInfo(address: InsteonAddress(0x15, 0xAA, 0xBB), category: 0x03, subcategory: 0x21, firmwareVersion: 0x93))
    ])

  }

  @Test func parsesModemConfigurationStartingWithNAKByte() {

    var parser = ModemReplyParser()

    let replies = parser.parse(bytes("0273" + "15" + "05" + "00" + "06"))

    #expect(replies == [.modemConfiguration(ModemConfigurationReport(
      configuration: ModemConfiguration(rawValue: 0x15),
      applicationRetries: 0x05,
      databaseDelta: 0x00
    ))])

  }

  @Test func reportsARejectedInfoRequestOnceTheNextReplyArrives() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("026015")).isEmpty)
    #expect(parser.parse(bytes("0260" + "112233" + "03" + "21" + "93" + "06")) == [
      .echo(CommandEcho(number: .getModemInfo, parameters: [], isAccepted: false)),
      .modemInfo(ModemInfo(address: Self.modem, category: 0x03, subcategory: 0x21, firmwareVersion: 0x93))
    ])

  }

  @Test func reportsARejectedConfigurationRequestOnceTheNextReplyArrives() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("027315" + "0255" + "0255")) == [
      .echo(CommandEcho(number: .getModemConfiguration, parameters: [], isAccepted: false)),
      .userReset,
      .userReset
    ])

  }

  // A busy modem NAKs Get IM Configuration, then reports a message from a device whose
  // address starts with 0x06. Read on, `02 73 15 02 50 06` would be a configuration of 0x15.
  @Test func endsARejectedConfigurationRequestAtAMessageFromADeviceStartingWithAnACKByte() {

    var parser = ModemReplyParser()
    let sender = InsteonAddress(0x06, 0xBB, 0xCC)

    #expect(parser.parse(bytes("027315" + "0250" + "06BBCC" + "112233" + "2B" + "11FF")) == [
      .echo(CommandEcho(number: .getModemConfiguration, parameters: [], isAccepted: false)),
      .messageReceived(ReceivedMessage(
        sender: sender,
        destination: Self.modem,
        flags: MessageFlags(rawValue: 0x2B),
        command: Command(command1: 0x11, command2: 0xFF)
      ))
    ])

  }

  // The same for Get IM Info, followed by a direct message to a modem whose address starts
  // with 0x06: read on, the destination's first byte would be the reply's ACK.
  @Test func endsARejectedInfoRequestAtAMessageToAModemStartingWithAnACKByte() {

    var parser = ModemReplyParser()
    let modem = InsteonAddress(0x06, 0x22, 0x33)

    #expect(parser.parse(bytes("026015" + "0250" + "AABBCC" + "062233" + "2B" + "11FF")) == [
      .echo(CommandEcho(number: .getModemInfo, parameters: [], isAccepted: false)),
      .messageReceived(ReceivedMessage(
        sender: Self.device,
        destination: modem,
        flags: MessageFlags(rawValue: 0x2B),
        command: Command(command1: 0x11, command2: 0xFF)
      ))
    ])

  }

  @Test func endsARejectedRadioStatusRequestAtTheNextReply() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("027E15" + "025806" + "0255")) == [
      .echo(CommandEcho(number: .readRadioStatus, parameters: [], isAccepted: false)),
      .allLinkCleanupStatus(isComplete: true),
      .userReset
    ])

  }

  // A reply whose data starts the way a NAK and the next frame would is read as the NAK, so
  // the command is sent again rather than a made-up configuration accepted.
  @Test func readsAnAmbiguousConfigurationAsARejection() {

    var parser = ModemReplyParser()

    #expect(parser.parse(bytes("027315" + "025006")).first == .echo(CommandEcho(number: .getModemConfiguration, parameters: [], isAccepted: false)))

  }

  @Test func reportsAFullLengthRejectedInfoRequestWithoutParameters() {

    var parser = ModemReplyParser()

    let replies = parser.parse(bytes("0260" + "112233" + "03" + "21" + "93" + "15"))

    #expect(replies == [.echo(CommandEcho(number: .getModemInfo, parameters: [], isAccepted: false))])

  }

  @Test func recoversFromAStartByteThatDoesntBeginAReply() {

    var parser = ModemReplyParser()

    // The first frame looks like the start of an extended message's echo, but the bytes that
    // follow are other replies, so it never ends in an ACK or NAK.
    let replies = parser.parse(bytes(
      "0262" + "AABBCC" + "1F"
        + "0250" + "AABBCC" + "112233" + "2B" + "11FF"
        + "025806" + "0255" + "0255"
    ))

    #expect(replies == [
      .messageReceived(ReceivedMessage(
        sender: Self.device,
        destination: Self.modem,
        flags: MessageFlags(rawValue: 0x2B),
        command: Command(command1: 0x11, command2: 0xFF)
      )),
      .allLinkCleanupStatus(isComplete: true),
      .userReset,
      .userReset
    ])

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

  static let buttonEvents: [(UInt8, ModemButtonEvent.Button, ModemButtonEvent.Action)] = [
    (0x02, .set, .tapped),
    (0x03, .set, .held),
    (0x04, .set, .released),
    (0x12, .button2, .tapped),
    (0x13, .button2, .held),
    (0x14, .button2, .released),
    (0x22, .button3, .tapped),
    (0x23, .button3, .held),
    (0x24, .button3, .released)
  ]

  // The event codes in Insteon's modem documentation.
  @Test(arguments: buttonEvents)
  func decodesButtonEvent(_ code: UInt8, _ button: ModemButtonEvent.Button, _ action: ModemButtonEvent.Action) {

    let event = ModemButtonEvent(rawValue: code)

    #expect(event.button == button)
    #expect(event.action == action)
    #expect(ModemButtonEvent(button: button, action: action) == event)

  }

  @Test func keepsAnUnknownButtonEventCode() {

    let event = ModemButtonEvent(rawValue: 0x35)

    #expect(event.button == nil)
    #expect(event.action == nil)
    #expect(event.rawValue == 0x35)

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
      flags: MessageFlags(messageType: .directNegativeAcknowledgment),
      command: Command(command1: 0x11, command2: 0xFF)
    )
    let ack = ReceivedMessage(
      sender: nak.sender,
      destination: nak.destination,
      flags: MessageFlags(messageType: .directAcknowledgment),
      command: Command(command1: 0x11, command2: 0xFF)
    )

    #expect(nak.nakReason == .notLinked)
    #expect(ack.nakReason == nil)

  }

}
