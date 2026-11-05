import Testing
import InsteonProtocol

struct DeviceDatabaseLayoutTests {

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  @Test func theRecordBelowIsEightLowerDownToTheLowest() {

    #expect(DeviceDatabaseLayout.address(below: 0x0FFF) == 0x0FF7)
    #expect(DeviceDatabaseLayout.address(below: 0x030F) == 0x0307)
    #expect(DeviceDatabaseLayout.address(below: 0x0307) == nil)
    #expect(DeviceDatabaseLayout.address(below: 0x0000) == nil)

  }

  @Test func countsTheRecordsThatFitBelowARecord() {

    #expect(DeviceDatabaseLayout.recordCount(below: 0x0FFF) == 415)
    #expect(DeviceDatabaseLayout.recordCount(below: 0x030F) == 1)
    #expect(DeviceDatabaseLayout.recordCount(below: 0x0307) == 0)
    #expect(DeviceDatabaseLayout.recordCount(below: 0x0000) == 0)

  }

  @Test func aLinkWritesE2ForAControllerAndA2ForAResponder() {

    #expect(AllLinkRecordFlags.linked(isController: true).rawValue == 0xE2)
    #expect(AllLinkRecordFlags.linked(isController: false).rawValue == 0xA2)

  }

  @Test func theEndOfADatabaseIsAllZeros() {

    #expect(AllLinkRecord.endOfDatabase.bytes == [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

  }

  @Test func recordsMatchButForTheFlagsADeviceMaintains() {

    let record = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: device, data1: 0xFF)
    var hopped = record
    hopped.flags = AllLinkRecordFlags(rawValue: 0xBB)
    var otherData = record
    otherData.data1 = 0x80
    var otherRole = record
    otherRole.flags = AllLinkRecordFlags(rawValue: 0xE2)

    #expect(record.equalsIgnoringDeviceMaintained(hopped))
    #expect(!record.equalsIgnoringDeviceMaintained(otherData))
    #expect(!record.equalsIgnoringDeviceMaintained(otherRole))

  }

  @Test(arguments: [(UInt8(0x22), true), (UInt8(0x62), true), (UInt8(0xA2), false), (UInt8(0x00), false)])
  func aSlotIsReusableWhenUsedBeforeAndNotInUse(flags: UInt8, isReusable: Bool) {

    let response = AllLinkRecordResponse(sender: device, address: 0x0FF7, record: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: flags), group: 0x01, address: device))

    #expect(response.isReusable == isReusable)

  }

  @Test func addsAModemRecordInItsRole() {

    let controller = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: device)
    let responder = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: device)

    #expect(SerialCommand.addAllLinkRecord(controller) == .manageAllLinkRecord(action: .modifyFirstControllerOrAdd, record: controller))
    #expect(SerialCommand.addAllLinkRecord(responder) == .manageAllLinkRecord(action: .modifyFirstResponderOrAdd, record: responder))

  }

  @Test func deletesTheModemsFirstRecordByGroupAndAddress() {

    #expect(
      SerialCommand.deleteFirstAllLinkRecord(group: 0x05, address: device)
        == .manageAllLinkRecord(action: .deleteFirst, record: AllLinkRecord(flags: [], group: 0x05, address: device))
    )

  }

}
