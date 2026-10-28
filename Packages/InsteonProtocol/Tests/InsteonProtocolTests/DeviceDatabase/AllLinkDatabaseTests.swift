import Testing
import InsteonProtocol

struct AllLinkDatabaseTests {

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  let record = AllLinkRecord(
    // In use, controller and used before, with product-specific bit 5 set as in Insteon's example.
    flags: AllLinkRecordFlags(rawValue: 0xE2),
    group: 0x04,
    address: InsteonAddress(0x00, 0x5E, 0x5D),
    data3: 0x04
  )

  @Test(arguments: [
    (AllLinkDatabaseRequest.readAll, [UInt8](repeating: 0x00, count: 14)),
    (.read(address: 0x0FF7), [0x00, 0x00, 0x0F, 0xF7, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  ])
  func encodesReads(_ request: AllLinkDatabaseRequest, _ expected: [UInt8]) {

    #expect(request.userData.bytes == expected)

  }

  @Test func encodesAWrite() {

    let request = AllLinkDatabaseRequest.write(record, address: 0x0FFF)

    #expect(request.userData.bytes == [0x00, 0x02, 0x0F, 0xFF, 0x08, 0xE2, 0x04, 0x00, 0x5E, 0x5D, 0x00, 0x00, 0x04, 0x00])

  }

  @Test func sendsTheRequestInAnExtendedMessageWithAChecksum() {

    let message = AllLinkDatabaseRequest.read(address: 0x0000).message(to: device)

    #expect(message.command == Command(command1: 0x2F, command2: 0x00))
    #expect(message.flags.isExtended)
    // The checksum in D14 makes cmd1, cmd2 and D1 through D14 sum to zero.
    #expect(message.bytes.suffix(16).reduce(0) { $0 + Int($1) } % 256 == 0)

  }

  // Insteon's example dump: the first record of a KeypadLinc that controls device 00.5E.5D
  // from button 4.
  @Test func readsARecordResponse() throws {

    let message = ReceivedMessage(
      sender: device,
      destination: InsteonAddress(0x11, 0x22, 0x33),
      flags: .extendedDirect,
      command: Command(command1: 0x2F, command2: 0x00),
      userData: try UserData([0x00, 0x01, 0x0F, 0xFF, 0x00, 0xE2, 0x04, 0x00, 0x5E, 0x5D, 0x00, 0x00, 0x04])
    )

    let response = try #require(AllLinkRecordResponse(message))

    // The guide's example predates i2cs, so it carries no checksum.
    #expect(response == AllLinkRecordResponse(
      sender: device,
      address: 0x0FFF,
      record: record,
      hasIntactChecksum: false
    ))
    #expect(!response.isEndOfDatabase)

  }

  // A response logged in Insteon's command workbook, whose D14 is the i2cs checksum.
  @Test func checksTheChecksumAnI2csDeviceSends() throws {

    var data = try UserData([0x00, 0x01, 0x0F, 0xFF, 0x00, 0xE2, 0x01, 0x13, 0xD0, 0x91, 0x05, 0x1C, 0x01])
    data[14] = 0x49

    func response(_ userData: UserData) -> AllLinkRecordResponse? {

      AllLinkRecordResponse(ReceivedMessage(
        sender: device,
        destination: InsteonAddress(0x11, 0x22, 0x33),
        flags: .extendedDirect,
        command: Command(command1: 0x2F, command2: 0x00),
        userData: userData
      ))

    }

    #expect(response(data)?.hasIntactChecksum == true)
    #expect(ChecksumIntegrity().isIntact(data, for: Command(command1: 0x2F, command2: 0x00)))

    data[9] = 0x00

    #expect(response(data)?.hasIntactChecksum == false)

  }

  @Test func recognizesTheRecordThatEndsTheDatabase() {

    let end = AllLinkRecordResponse(
      sender: device,
      address: 0x0FEF,
      record: AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))
    )

    #expect(end.isEndOfDatabase)

  }

  @Test func ignoresARequestEchoedBack() throws {

    // D2 0x00 is a request, not a response.
    let message = ReceivedMessage(
      sender: device,
      destination: InsteonAddress(0x11, 0x22, 0x33),
      flags: .extendedDirect,
      command: Command(command1: 0x2F, command2: 0x00),
      userData: AllLinkDatabaseRequest.read(address: 0x0FFF).userData
    )

    #expect(AllLinkRecordResponse(message) == nil)

  }

}
