import Testing
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol

/// Writing and reading one record of a device's database through a modem.
@Suite(.timeLimit(.minutes(1)))
struct DeviceDatabaseAccessTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let timeout: Duration = .seconds(7)

  let record = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: InsteonAddress(0x11, 0x22, 0x33), data1: 0xFF)

  @Test func writesARecordWithOneMessage() async throws {

    let memory = InMemoryModem()
    let modem = RecordingModem(memory)

    try await modem.writeAllLinkRecord(record, at: 0x0FFF, of: lamp, timeout: timeout)

    #expect(await modem.calls == [.extendedRequest(AllLinkDatabaseRequest.write(record, address: 0x0FFF).message(to: lamp), timeout: timeout)])
    #expect(await memory.record(of: lamp, at: 0x0FFF) == record)

  }

  @Test func readsAnIntactRecordOnce() async throws {

    let memory = InMemoryModem()

    await memory.setDatabase([0x0FFF: record], of: lamp)

    let modem = RecordingModem(memory)
    let read = try await modem.readAllLinkRecordCheckingIntegrity(of: lamp, at: 0x0FFF, timeout: timeout)

    #expect(read.record == record)
    #expect(await modem.calls == [.readAllLinkRecord(lamp, address: 0x0FFF, timeout: timeout)])

  }

  @Test func returnsADamagedRecordWhenNotAskedToReadItAgain() async throws {

    let memory = InMemoryModem()

    await memory.setDatabase([0x0FFF: record], of: lamp)
    await memory.setDamaged(true, record: 0x0FFF, of: lamp)

    let modem = RecordingModem(memory)
    let read = try await modem.readAllLinkRecord(of: lamp, at: 0x0FFF, timeout: timeout)

    #expect(!read.hasIntactChecksum)
    #expect(await modem.calls == [.readAllLinkRecord(lamp, address: 0x0FFF, timeout: timeout)])

  }

  @Test func readsADamagedRecordOnceMoreThenTimesOut() async throws {

    let memory = InMemoryModem()

    await memory.setDatabase([0x0FFF: record], of: lamp)
    await memory.setDamaged(true, record: 0x0FFF, of: lamp)

    let modem = RecordingModem(memory)

    await #expect(throws: ModemError.deviceTimedOut(lamp)) {

      _ = try await modem.readAllLinkRecordCheckingIntegrity(of: self.lamp, at: 0x0FFF, timeout: self.timeout)

    }

    #expect(await modem.calls == [
      .readAllLinkRecord(lamp, address: 0x0FFF, timeout: timeout),
      .readAllLinkRecord(lamp, address: 0x0FFF, timeout: timeout)
    ])

  }

  @Test func aSlotHoldsARecordButForTheFlagsADeviceMaintains() async throws {

    let memory = InMemoryModem()
    var hopped = record
    hopped.flags = AllLinkRecordFlags(rawValue: 0xBA)
    var other = record
    other.data1 = 0x80

    await memory.setDatabase([0x0FFF: hopped], of: lamp)

    #expect(try await memory.slotHolds(record, at: 0x0FFF, of: lamp, timeout: timeout, checkingIntegrity: false))
    #expect(try await !memory.slotHolds(other, at: 0x0FFF, of: lamp, timeout: timeout, checkingIntegrity: false))

  }

}
