import Testing
import InsteonLinking
import InsteonModem
import InsteonProtocol

struct AllLinkDatabaseCacheTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let keypad = InsteonAddress(0x00, 0x5E, 0x5D)

  let link = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: InsteonAddress(0x00, 0x5E, 0x5D))

  func group(controller: LinkEndpoint) -> AllLinkGroup {

    AllLinkGroup(
      controller: controller,
      number: 0x05,
      responders: [.init(.device(lamp), data1: 0xFF, data2: 0x1F, data3: 0x01)]
    )

  }

  @Test func readsADevicesDatabaseOnceWhileItsDeltaStaysTheSame() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: lamp)
    let cache = AllLinkDatabaseCache(modem: modem)

    let first = try await cache.records(of: lamp)
    let second = try await cache.records(of: lamp)

    #expect(first == second)
    #expect(first.first?.record == link)
    #expect(await modem.databaseReads[lamp] == 1)

  }

  @Test func readsADevicesDatabaseAgainOnceItChanges() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: lamp)
    let cache = AllLinkDatabaseCache(modem: modem)

    _ = try await cache.records(of: lamp)
    await modem.changeDatabase(of: lamp)
    _ = try await cache.records(of: lamp)

    #expect(await modem.databaseReads[lamp] == 2)

  }

  @Test func readsADevicesDatabaseAgainOnceItsForgotten() async throws {

    let modem = InMemoryModem()
    let cache = AllLinkDatabaseCache(modem: modem)

    _ = try await cache.records(of: lamp)
    await cache.invalidate(lamp)
    _ = try await cache.records(of: lamp)

    #expect(await modem.databaseReads[lamp] == 2)

  }

  @Test func readsTheModemsDatabaseOnceUntilItsForgotten() async throws {

    let modem = InMemoryModem()
    await modem.setModemRecords([link])
    let cache = AllLinkDatabaseCache(modem: modem)

    let records = try await cache.modemRecords()
    _ = try await cache.modemRecords()

    #expect(records == [link])
    #expect(await modem.modemDatabaseReads == 1)

    await cache.invalidateModem()
    _ = try await cache.modemRecords()

    #expect(await modem.modemDatabaseReads == 2)

  }

  // The device is the source of truth, so a database the linker changed is read again rather
  // than kept as the linker wrote it.
  @Test func readsADatabaseAgainAfterTheLinkerChangesIt() async throws {

    let modem = InMemoryModem()
    let cache = AllLinkDatabaseCache(modem: modem)

    try await Linker(modem: modem, cache: cache).link(group(controller: .device(keypad)))
    let records = try await cache.records(of: lamp)

    #expect(records.first?.record.address == keypad)
    #expect(await modem.databaseReads[lamp] == 2)

  }

  @Test func readsAnUnchangedDatabaseOnlyOnceAcrossLinks() async throws {

    let modem = InMemoryModem()
    let cache = AllLinkDatabaseCache(modem: modem)
    let linker = Linker(modem: modem, cache: cache)

    try await linker.link(group(controller: .device(keypad)))
    try await linker.link(group(controller: .device(keypad)))
    try await linker.link(group(controller: .device(keypad)))

    // The second link reads the databases the first changed; the third finds them unchanged.
    #expect(await modem.databaseReads[lamp] == 2)
    #expect(await modem.databaseReads[keypad] == 2)

  }

  @Test func forgetsTheModemsDatabaseWhenTheLinkerChangesIt() async throws {

    let modem = InMemoryModem()
    let cache = AllLinkDatabaseCache(modem: modem)

    _ = try await cache.modemRecords()
    try await Linker(modem: modem, cache: cache).link(group(controller: .modem))
    let records = try await cache.modemRecords()

    #expect(records.map(\.address) == [lamp])
    #expect(await modem.modemDatabaseReads == 2)

  }

}
