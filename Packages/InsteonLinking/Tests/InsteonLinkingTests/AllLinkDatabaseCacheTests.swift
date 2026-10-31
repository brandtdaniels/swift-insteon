import Testing
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

@Suite(.timeLimit(.minutes(1)))
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

  // A link is made while the modem's database is being read: the read in progress is
  // returned, but the next call reads the database again rather than keep the stale copy.
  @Test(.timeLimit(.minutes(1)))
  func doesntKeepAModemReadThatWasForgottenWhileInProgress() async throws {

    let modem = InMemoryModem()
    let before = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: lamp)
    let added = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x02, address: keypad)
    await modem.setModemRecords([before])
    let cache = AllLinkDatabaseCache(modem: modem)

    let (reached, reachedSignal) = AsyncStream<Void>.makeStream()
    let (release, releaseSignal) = AsyncStream<Void>.makeStream()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      guard case .readModemDatabase = operation else {

        return

      }

      reachedSignal.yield()

      for await _ in release {

        break

      }

    }

    let reading = Task { try await cache.modemRecords() }
    var reachedRead = reached.makeAsyncIterator()
    _ = await reachedRead.next()

    // The read has taken its copy; the link changes the modem's database meanwhile.
    await modem.setBeforeOperation(nil)
    await modem.setModemRecords([before, added])
    await cache.invalidateModem()
    releaseSignal.yield()

    #expect(try await reading.value == [before])
    #expect(try await cache.modemRecords() == [before, added])
    #expect(await modem.modemDatabaseReads == 2)

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

  @Test func reportsTheStatusAndWhetherItReadTheDatabase() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: lamp)
    await modem.setLevel(0x80, of: lamp)
    let cache = AllLinkDatabaseCache(modem: modem)

    let first: AllLinkDatabaseReading = try await cache.database(of: lamp)
    let second: AllLinkDatabaseReading = try await cache.database(of: lamp)

    #expect(first.wasRead)
    #expect(!second.wasRead)
    #expect(first.status == 0x80)
    #expect(second.copy == first.copy)
    #expect(await cache.copies == [lamp: first.copy])

  }

  @Test func handsBackACopyItStartedWithWhileTheDeltaMatches() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: lamp)
    let kept = AllLinkDatabaseCopy(delta: 0x00, records: [AllLinkRecordResponse(sender: lamp, address: 0x0FFF, record: link)])
    let cache = AllLinkDatabaseCache(modem: modem, copies: [lamp: kept])

    let records: [AllLinkRecordResponse] = try await cache.records(of: lamp)

    #expect(records == kept.records)
    #expect(await modem.databaseReads[lamp] == nil)

    await modem.changeDatabase(of: lamp)
    _ = try await cache.records(of: lamp)

    #expect(await modem.databaseReads[lamp] == 1)

  }

  @Test func doesntKeepACopyWithARecordWhoseChecksumFailed() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: lamp)
    await modem.setDamaged(true, record: 0x0FFF, of: lamp)
    let cache = AllLinkDatabaseCache(modem: modem)

    let damaged: AllLinkDatabaseReading = try await cache.database(of: lamp)

    #expect(damaged.wasRead)
    #expect(!damaged.copy.hasIntactChecksums)
    #expect(await cache.copies[lamp] == nil)

    await modem.setDamaged(false, record: 0x0FFF, of: lamp)

    let whole: AllLinkDatabaseReading = try await cache.database(of: lamp)
    let again: AllLinkDatabaseReading = try await cache.database(of: lamp)

    #expect(whole.wasRead)
    #expect(whole.copy.hasIntactChecksums)
    #expect(!again.wasRead)
    #expect(await cache.copies[lamp] == whole.copy)
    #expect(await modem.databaseReads[lamp] == 2)

  }

  @Test func leavesOutACopyItStartedWithThatHasARecordWhoseChecksumFailed() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: lamp)
    let damaged = AllLinkDatabaseCopy(delta: 0x00, records: [AllLinkRecordResponse(sender: lamp, address: 0x0FFF, record: link, hasIntactChecksum: false)])
    let cache = AllLinkDatabaseCache(modem: modem, copies: [lamp: damaged])

    #expect(await cache.copies.isEmpty)

    _ = try await cache.records(of: lamp)

    #expect(await modem.databaseReads[lamp] == 1)

  }

}
