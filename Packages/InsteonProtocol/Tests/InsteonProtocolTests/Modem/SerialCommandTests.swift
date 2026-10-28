import Testing
import InsteonProtocol

struct SerialCommandTests {

  static let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)

  static let record = AllLinkRecord(
    flags: [.inUse, .controller, .usedBefore],
    group: 0x01,
    address: lamp,
    data1: 0x03,
    data2: 0x1F,
    data3: 0x01
  )

  static let encodings: [(SerialCommand, String)] = [
    (.getModemInfo, "0260"),
    (.sendAllLinkCommand(group: 0x01, command: Command(command1: 0x11, command2: 0xFF)), "02610111FF"),
    (.sendStandardMessage(StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))), "0262AABBCC0F11FF"),
    (.sendX10(.unit(.a, .one)), "02636600"),
    (.sendX10(.command(.a, .on)), "02636280"),
    (.startAllLinking(mode: .controller, group: 0x01), "02640101"),
    (.startAllLinking(mode: .delete, group: 0x00), "0264FF00"),
    (.startAllLinkingWithLinkData(mode: .responder, group: 0x01), "02640401"),
    (.cancelAllLinking, "0265"),
    (.setHostDeviceCategory(category: 0x03, subcategory: 0x15, firmwareVersion: nil), "02660315FF"),
    (.resetModem, "0267"),
    (.setAcknowledgmentByte(0x01), "026801"),
    (.getFirstAllLinkRecord, "0269"),
    (.getNextAllLinkRecord, "026A"),
    (.setModemConfiguration([.monitorMode, .disableAutomaticLinking]), "026BC0"),
    (.getAllLinkRecordForSender, "026C"),
    (.ledOn, "026D"),
    (.ledOff, "026E"),
    (.manageAllLinkRecord(action: .modifyFirstControllerOrAdd, record: record), "026F40C201AABBCC031F01"),
    (.setNegativeAcknowledgmentByte(0x02), "027002"),
    (.setAcknowledgmentBytes(Command(command1: 0x11, command2: 0xFF)), "027111FF"),
    (.rfSleep, "0272"),
    (.getModemConfiguration, "0273"),
    (.cancelCleanup, "0274"),
    (.readDatabase(address: 0x0FF8), "02750FF8"),
    (.writeDatabase(address: 0x0FF8, record: record), "02760FF8C201AABBCC031F01"),
    (.beep, "0277"),
    (.setResponderLinkData(data1: 0xFF, data2: 0x1F, data3: 0x03), "0279FF1F03"),
    (.setApplicationRetries(0x05), "027A05"),
    (.setRadio(.enabled), "027D80"),
    (.setRadio(.disabled), "027D81"),
    (.setRadio(.enabledUntilPowerCycle), "027D00"),
    (.setRadio(.disabledUntilPowerCycle), "027D01"),
    (.readRadioStatus, "027E"),
    (.readDiagnostics(index: 0x08), "028108"),
    // Insteon's command workbook: modify the 0xA2 record for group 7 and 10.A3.0F, then delete
    // the 0xE2 record.
    (
      .manageDeviceRecord(DeviceRecordRequest(
        device: InsteonAddress(0x08, 0xB6, 0xEA),
        record: AllLinkRecord(flags: [.inUse], group: 0x07, address: InsteonAddress(0x10, 0xA3, 0x0F), data1: 0x07, data2: 0x1C),
        options: [.modify]
      )),
      "028208B6EA020710A30F071C00"
    ),
    (
      .manageDeviceRecord(DeviceRecordRequest(
        device: InsteonAddress(0x08, 0xB6, 0xEA),
        record: AllLinkRecord(flags: [.inUse, .controller], group: 0x07, address: InsteonAddress(0x10, 0xA3, 0x0F), data1: 0x7F, data2: 0x1C),
        options: [.delete]
      )),
      "028208B6EA440710A30F7F1C00"
    )
  ]

  @Test(arguments: encodings)
  func encodes(_ command: SerialCommand, _ expected: String) {

    #expect(command.hexString == expected)

  }

  @Test(arguments: encodings)
  func numberMatchesTheEncodedCommandNumber(_ command: SerialCommand, _ expected: String) {

    let number = String(command.number.rawValue, radix: 16, uppercase: true)

    #expect(expected.dropFirst(2).hasPrefix(number))

  }

  @Test func encodesExtendedMessageWithItsChecksum() throws {

    let message = ExtendedMessage(
      to: Self.lamp,
      command: ExtendedDirectCommand.getSet(),
      userData: try UserData([0x01])
    )

    #expect(
      SerialCommand.sendExtendedMessage(message).hexString
        == "0262AABBCC1F2E00" + "01" + String(repeating: "00", count: 12) + "D1"
    )

  }

  @Test func sendAllLinkCommandPutsGroupBeforeCommandBytes() {

    let command = SerialCommand.sendAllLinkCommand(group: 0x05, command: Command(command1: 0x13))

    #expect(command.parameters == [0x05, 0x13, 0x00])

  }

}
