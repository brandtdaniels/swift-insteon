import Testing
import InsteonProtocol

/// The encodings come from the worked examples in the INSTEON Developer's Guide, chapter 9,
/// including their checksums.
struct IBIOSTests {

  static let encodings: [(IBIOSCommand, String)] = [
    (.getVersion, "0248"),
    // Sending ON to 00.02.AC: the message goes into the construction buffer.
    (.download(address: 0x01A4, data: [0x00, 0x02, 0xAC, 0x0F, 0x11, 0xFF]), "024001A40006FD880002AC0F11FF"),
    // Writing 55 AA 55 AA to the external EEPROM.
    (.download(address: 0x0300, data: [0x55, 0xAA, 0x55, 0xAA]), "0240030000" + "04FDFB55AA55AA"),
    // Loading the X10 address A1.
    (.download(address: 0x0165, data: [0x66]), "02400165" + "0001FF3366"),
    (.mask(address: 0x0142, or: 0x10, and: 0xFF), "0246014210FF"),
    (.mask(address: 0x0166, or: 0x80, and: 0xF7), "0246016680F7"),
    (.upload(address: 0x0300, length: 4), "024203000004"),
    (.getChecksum(address: 0x0230, length: 0x000A), "02440230000A"),
    (.simulateEvent(.buttonTapped, timer: 0), "02470A00")
  ]

  @Test(arguments: encodings)
  func encodes(_ command: IBIOSCommand, _ expected: String) {

    #expect(command.hexString == expected)

  }

  static let device = InsteonAddress(0x00, 0x02, 0xAC)

  static let controller = InsteonAddress(0x1A, 0x2B, 0x3C)

  static let replies: [(String, IBIOSReply)] = [
    ("024001A4000606", .echo(IBIOSEcho(number: 0x40, parameters: [0x01, 0xA4, 0x00, 0x06], isAccepted: true))),
    ("0246014210FF06", .echo(IBIOSEcho(number: 0x46, parameters: [0x01, 0x42, 0x10, 0xFF], isAccepted: true))),
    ("02470A0006", .echo(IBIOSEcho(number: 0x47, parameters: [0x0A, 0x00], isAccepted: true))),
    ("024001A4000615", .echo(IBIOSEcho(number: 0x40, parameters: [0x01, 0xA4, 0x00, 0x06], isAccepted: false))),
    (
      "0248" + "1A2B3C" + "0302" + "FF" + "06",
      .version(ModemInfo(address: controller, category: 0x03, subcategory: 0x02, firmwareVersion: 0xFF))
    ),
    ("0242" + "0300" + "0004" + "55AA55AA" + "FDFB" + "06", .memory(address: 0x0300, data: [0x55, 0xAA, 0x55, 0xAA], isIntact: true)),
    ("0242" + "0300" + "0004" + "55AA55AA" + "0000" + "06", .memory(address: 0x0300, data: [0x55, 0xAA, 0x55, 0xAA], isIntact: false)),
    ("0244" + "0230" + "000A" + "1234" + "06", .checksum(address: 0x0230, length: 0x000A, checksum: 0x1234)),
    ("02450A", .eventReport(.buttonTapped)),
    ("024F05", .messageReceived(.sendNotAcknowledged, message: nil)),
    (
      "024F01" + "0002AC" + "1A2B3C" + "2B" + "11FF",
      .messageReceived(.messageForMe, message: ReceivedMessage(
        sender: device,
        destination: controller,
        flags: MessageFlags(rawValue: 0x2B),
        command: Command(command1: 0x11, command2: 0xFF)
      ))
    ),
    ("024A0066", .x10Received(.unit(.a, .one))),
    ("024A0162", .x10Received(.command(.a, .on))),
    ("02490237", .debugReport(address: 0x0237)),
    ("024103" + "010203", .data([0x01, 0x02, 0x03])),
    ("0243" + "427574746F6E" + "03", .text("Button")),
    ("15", .negativeAcknowledgement)
  ]

  @Test(arguments: replies)
  func parsesReply(_ hex: String, _ expected: IBIOSReply) {

    var parser = IBIOSReplyParser()

    #expect(parser.parse(bytes(hex)) == [expected])

  }

  @Test func parsesExtendedMessages() throws {

    var parser = IBIOSReplyParser()
    let userData = Array(UInt8(1)...14)

    let replies = parser.parse(bytes("024F01" + "0002AC" + "1A2B3C" + "1B" + "2E00") + userData)

    #expect(replies == [.messageReceived(.messageForMe, message: ReceivedMessage(
      sender: Self.device,
      destination: Self.controller,
      flags: MessageFlags(rawValue: 0x1B),
      command: Command(command1: 0x2E, command2: 0x00),
      userData: try UserData(userData)
    ))])

  }

  @Test func waitsForTheRestOfASplitReply() {

    var parser = IBIOSReplyParser()
    let frame = bytes("0248" + "1A2B3C" + "0302" + "FF" + "06")

    #expect(parser.parse(frame.prefix(4)).isEmpty)
    #expect(parser.parse(frame.dropFirst(4)).count == 1)

  }

  @Test func reportsARejectedRequestOnceTheNextReplyArrives() {

    var parser = IBIOSReplyParser()

    #expect(parser.parse(bytes("024815")).isEmpty)
    #expect(parser.parse(bytes("02450A" + "02450B" + "02450C")) == [
      .echo(IBIOSEcho(number: 0x48, parameters: [], isAccepted: false)),
      .eventReport(.buttonTapped),
      .eventReport(.buttonHeld),
      .eventReport(.buttonReleased)
    ])

  }

  @Test func finishesARejectedRequestWhenNoMoreBytesCome() {

    var parser = IBIOSReplyParser()

    #expect(parser.parse(bytes("024815")).isEmpty)
    #expect(parser.finishPendingReply() == [.echo(IBIOSEcho(number: 0x48, parameters: [], isAccepted: false))])

  }

  @Test func skipsNoiseAndUnknownNumbers() {

    var parser = IBIOSReplyParser()

    #expect(parser.parse(bytes("FF00" + "0299" + "15" + "02450A")) == [.eventReport(.buttonTapped)])

  }

  @Test func computesChecksumsAsTwosComplementOfTheSum() {

    #expect(IBIOSCommand.checksum(of: [0x03, 0x00, 0x00, 0x04, 0x55, 0xAA, 0x55, 0xAA]) == 0xFDFB)
    #expect(IBIOSCommand.checksum(of: []) == 0)

  }

  private func bytes(_ hex: String) -> [UInt8] {

    let digits = Array(hex)

    return stride(from: 0, to: digits.count, by: 2).map { UInt8(String(digits[$0..<$0 + 2]), radix: 16)! }

  }

}
