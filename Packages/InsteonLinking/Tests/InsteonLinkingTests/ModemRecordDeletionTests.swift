import Testing
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Deleting a gone device's records from the modem's own ALL-Link database.
struct ModemRecordDeletionTests {

  let sensor = InsteonAddress(0x4C, 0x5D, 0x01)

  let lamp = InsteonAddress(0x4C, 0x5D, 0x02)

  @Test func deletesEveryRecordThatNamesTheDeviceAndNoOther() async throws {

    let modem = InMemoryModem()
    let controller = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: sensor)
    let responder = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: sensor)
    let sameGroup = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x00, address: sensor)
    let other = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp)
    await modem.setModemRecords([controller, other, responder, sameGroup])

    let deleted: [AllLinkRecord] = try await Unlinker(modem: modem).deleteModemRecords(of: sensor)

    #expect(deleted == [controller, responder, sameGroup])
    #expect(await modem.modemRecords == [other])
    #expect(await modem.modemDeletions == 3)
    // The device itself is sent nothing.
    #expect(await modem.linkingSteps.isEmpty)

  }

  @Test func deletesNothingWhenTheModemHasNoRecordForTheDevice() async throws {

    let modem = InMemoryModem()
    let other = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: lamp)
    await modem.setModemRecords([other])

    let deleted: [AllLinkRecord] = try await Unlinker(modem: modem).deleteModemRecords(of: sensor)

    #expect(deleted.isEmpty)
    #expect(await modem.modemRecords == [other])
    #expect(await modem.modemDeletions == 0)

  }

  @Test func forgetsTheCachesCopyOfTheModemsRecords() async throws {

    let modem = InMemoryModem()
    let record = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: sensor)
    await modem.setModemRecords([record])
    let cache = AllLinkDatabaseCache(modem: modem)

    #expect(try await cache.modemRecords() == [record])

    try await Unlinker(modem: modem, cache: cache).deleteModemRecords(of: sensor)

    #expect(try await cache.modemRecords().isEmpty)

  }

}
