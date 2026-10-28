import Testing
import InsteonLinking
import InsteonModem
import InsteonProtocol

struct LinkerTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let keypad = InsteonAddress(0x00, 0x5E, 0x5D)

  let modemAddress = InsteonAddress(0x11, 0x22, 0x33)

  func group(controller: LinkEndpoint = .modem, responder: LinkEndpoint, onLevel: UInt8 = 0xFF) -> AllLinkGroup {

    AllLinkGroup(
      controller: controller,
      number: 0x05,
      responders: [.init(responder, data1: onLevel, data2: 0x1F, data3: 0x01)]
    )

  }

  func responderRecord(of controller: InsteonAddress, onLevel: UInt8 = 0xFF) -> AllLinkRecord {

    AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x05, address: controller, data1: onLevel, data2: 0x1F, data3: 0x01)

  }

  @Test func linksTheModemToADevice() async throws {

    let modem = InMemoryModem()

    try await Linker(modem: modem).link(group(responder: .device(lamp)))

    #expect(await modem.modemRecords == [AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x05, address: lamp)])
    #expect(await modem.record(of: lamp, at: 0x0FFF) == responderRecord(of: modemAddress))
    // The next record becomes the end of the database before the end is overwritten.
    #expect(await modem.writes == [.init(device: lamp, address: 0x0FF7), .init(device: lamp, address: 0x0FFF)])
    #expect(await modem.record(of: lamp, at: 0x0FF7).flags.isEmpty)

  }

  @Test func linksTwoDevicesWithoutAskingTheModemForItsAddress() async throws {

    let modem = InMemoryModem()

    try await Linker(modem: modem).link(group(controller: .device(keypad), responder: .device(lamp)))

    #expect(await modem.record(of: keypad, at: 0x0FFF) == AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x05, address: lamp))
    #expect(await modem.record(of: lamp, at: 0x0FFF) == responderRecord(of: keypad))
    #expect(await modem.wasAskedForItsAddress == false)

  }

  @Test func updatesAnExistingLinkInPlace() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: responderRecord(of: keypad, onLevel: 0x80)], of: lamp)

    try await Linker(modem: modem).link(group(controller: .device(keypad), responder: .device(lamp)))

    #expect(await modem.record(of: lamp, at: 0x0FFF) == responderRecord(of: keypad))
    #expect(await modem.writes.filter { $0.device == lamp } == [.init(device: lamp, address: 0x0FFF)])

  }

  @Test func leavesALinkThatsAlreadyRightAlone() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: responderRecord(of: keypad)], of: lamp)

    try await Linker(modem: modem).link(group(controller: .device(keypad), responder: .device(lamp)))

    #expect(await modem.writes.filter { $0.device == lamp }.isEmpty)

  }

  @Test func reusesARecordNoLongerInUse() async throws {

    let modem = InMemoryModem()
    let other = InsteonAddress(0x44, 0x55, 0x66)
    // A deleted record: used before, but no longer in use.
    let deleted = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0x01, address: other)
    await modem.setDatabase([0x0FFF: deleted, 0x0FF7: responderRecord(of: other)], of: lamp)

    try await Linker(modem: modem).link(group(controller: .device(keypad), responder: .device(lamp)))

    #expect(await modem.record(of: lamp, at: 0x0FFF) == responderRecord(of: keypad))
    #expect(await modem.record(of: lamp, at: 0x0FF7) == responderRecord(of: other))

  }

  @Test func throwsWhenADeviceIsntLinkedToTheModem() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(lamp)

    await #expect(throws: ModemError.deviceRejected(lamp, .notLinked)) {

      try await Linker(modem: modem).link(group(responder: .device(lamp)))

    }

  }

  @Test func throwsWhenARecordDoesntReadBack() async throws {

    let modem = InMemoryModem()
    await modem.setForgetful(lamp)

    await #expect(throws: LinkingError.recordNotWritten(lamp, address: 0x0FFF)) {

      try await Linker(modem: modem).link(group(controller: .device(keypad), responder: .device(lamp)))

    }

  }

  @Test func throwsWhenADatabaseIsFull() async throws {

    let modem = InMemoryModem()
    let other = InsteonAddress(0x44, 0x55, 0x66)
    let full = Dictionary(uniqueKeysWithValues: stride(from: UInt16(0x0FFF), to: 0x0000, by: -8).map {

      ($0, responderRecord(of: other))

    })
    await modem.setDatabase(full, of: lamp)

    await #expect(throws: LinkingError.databaseFull(lamp)) {

      try await Linker(modem: modem).link(group(controller: .device(keypad), responder: .device(lamp)))

    }

  }

  @Test func unlinksAGroup() async throws {

    let modem = InMemoryModem()
    let linked = group(responder: .device(lamp))

    try await Linker(modem: modem).link(linked)
    try await Unlinker(modem: modem).unlink(linked)

    #expect(await modem.modemRecords.isEmpty)
    // Deleting clears the in-use bit and keeps the used-before bit, so the record is reused.
    #expect(await modem.record(of: lamp, at: 0x0FFF).flags.rawValue == 0x22)

  }

  @Test func unlinkingSkipsLinksThatArentThere() async throws {

    let modem = InMemoryModem()

    try await Unlinker(modem: modem).unlink(group(responder: .device(lamp)))

    #expect(await modem.writes.isEmpty)

  }

}
