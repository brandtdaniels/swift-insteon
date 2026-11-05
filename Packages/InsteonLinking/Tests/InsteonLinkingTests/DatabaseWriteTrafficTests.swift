import Testing
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol

/// The exact calls ``Linker`` and ``Unlinker`` make to write and delete records, in order.
@Suite(.timeLimit(.minutes(1)))
struct DatabaseWriteTrafficTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)

  let timeout: Duration = .seconds(7)

  let end = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  var group: AllLinkGroup {

    AllLinkGroup(controller: .modem, number: 0x05, responders: [.init(.device(lamp), data1: 0xFF, data2: 0x1F, data3: 0x01)])

  }

  var responderRecord: AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x05, address: modemAddress, data1: 0xFF, data2: 0x1F, data3: 0x01)

  }

  var controllerRecord: AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x05, address: lamp)

  }

  func write(_ record: AllLinkRecord, at address: UInt16) -> RecordingModem.Call {

    .extendedRequest(AllLinkDatabaseRequest.write(record, address: address).message(to: lamp), timeout: timeout)

  }

  func read(at address: UInt16) -> RecordingModem.Call {

    .readAllLinkRecord(lamp, address: address, timeout: timeout)

  }

  @Test func linkingAtTheEndWritesTheNewEndFirstAndReadsEachWriteBack() async throws {

    let modem = RecordingModem(InMemoryModem())

    try await Linker(modem: modem, timeout: timeout).link(group)

    #expect(await modem.calls == [
      .modemInfo,
      .readAllLinkDatabase(lamp, timeout: timeout),
      write(end, at: 0x0FF7),
      read(at: 0x0FF7),
      write(responderRecord, at: 0x0FFF),
      read(at: 0x0FFF),
      .readModemRecords(group: 0x05, device: lamp),
      .send(.manageAllLinkRecord(action: .modifyFirstControllerOrAdd, record: controllerRecord))
    ])

  }

  @Test func linkingUpdatesARecordInPlaceAndReusesNoSlot() async throws {

    let memory = InMemoryModem()
    var old = responderRecord
    old.data1 = 0x80

    await memory.setDatabase([
      0x0FFF: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0x09, address: lamp),
      0x0FF7: old
    ], of: lamp)
    await memory.setModemRecords([controllerRecord])

    let modem = RecordingModem(memory)

    try await Linker(modem: modem, timeout: timeout).link(group)

    #expect(await modem.calls == [
      .modemInfo,
      .readAllLinkDatabase(lamp, timeout: timeout),
      write(responderRecord, at: 0x0FF7),
      read(at: 0x0FF7),
      .readModemRecords(group: 0x05, device: lamp)
    ])

  }

  @Test func linkingReusesTheFirstSlotNotInUse() async throws {

    let memory = InMemoryModem()

    await memory.setDatabase([
      0x0FFF: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: modemAddress),
      0x0FF7: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0x09, address: lamp)
    ], of: lamp)

    let modem = RecordingModem(memory)

    try await Linker(modem: modem, timeout: timeout).link(group)

    #expect(await modem.calls == [
      .modemInfo,
      .readAllLinkDatabase(lamp, timeout: timeout),
      write(responderRecord, at: 0x0FF7),
      read(at: 0x0FF7),
      .readModemRecords(group: 0x05, device: lamp),
      .send(.manageAllLinkRecord(action: .modifyFirstControllerOrAdd, record: controllerRecord))
    ])

  }

  @Test func linkingStopsAtAWriteThatDoesntReadBack() async throws {

    let memory = InMemoryModem()

    await memory.setForgetful(lamp)

    let modem = RecordingModem(memory)

    // The new end reads back as an end, since the slot held one already.
    await #expect(throws: LinkingError.recordNotWritten(lamp, address: 0x0FFF)) {

      try await Linker(modem: modem, timeout: self.timeout).link(self.group)

    }

    #expect(await modem.calls == [
      .modemInfo,
      .readAllLinkDatabase(lamp, timeout: timeout),
      write(end, at: 0x0FF7),
      read(at: 0x0FF7),
      write(responderRecord, at: 0x0FFF),
      read(at: 0x0FFF)
    ])

  }

  @Test func unlinkingDeletesTheModemsRecordsKeepingTheOtherRoleThenClearsTheDevicesRecord() async throws {

    let memory = InMemoryModem()
    let modemResponder = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x05, address: lamp)

    await memory.setDatabase([0x0FFF: responderRecord], of: lamp)
    await memory.setModemRecords([controllerRecord, modemResponder])

    let modem = RecordingModem(memory)

    try await Unlinker(modem: modem, timeout: timeout).unlink(group)

    var cleared = responderRecord
    cleared.flags.remove(.inUse)
    let key = AllLinkRecord(flags: [], group: 0x05, address: lamp)

    #expect(await modem.calls == [
      .modemInfo,
      .readModemRecords(group: 0x05, device: lamp),
      .send(.manageAllLinkRecord(action: .deleteFirst, record: key)),
      .send(.manageAllLinkRecord(action: .deleteFirst, record: key)),
      .send(.manageAllLinkRecord(action: .modifyFirstResponderOrAdd, record: modemResponder)),
      .readAllLinkDatabase(lamp, timeout: timeout),
      write(cleared, at: 0x0FFF),
      read(at: 0x0FFF)
    ])

  }

}
