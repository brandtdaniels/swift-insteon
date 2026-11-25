import Foundation
import InsteonLinkingTestSupport
import InsteonProtocol
import Testing
@testable import InsteonCore

/// A transfer carried out against the in-memory modem, which answers for the devices' databases.
@Suite(.timeLimit(.minutes(1)))
struct ModemTransferWriterTests {

  typealias Example = BackupExample

  /// The modem the backup was taken from. The in-memory modem is the new one.
  static let old = Example.newModem
  static let lamp = Example.lamp

  static func slotRecord(_ address: InsteonAddress, flags: AllLinkRecordFlags = [.inUse, .usedBefore]) -> AllLinkRecord {

    AllLinkRecord(flags: flags, group: AllLinkGroupNumber(rawValue: 1), address: address, data1: 0xFF, data2: 0x1F, data3: 0x01)

  }

  static func plan(_ modem: InMemoryModem) async throws -> TransferPlan {

    let held: [BackupRecord] = [Example.record(.responder, group: 1, old, memory: 0x0FFF), Example.end(0x0FF7)]
    let backup: HomeBackup = HomeBackup(
      createdAt: Example.createdAt,
      source: .modem,
      modem: BackupModem(address: old, allLinkDatabase: [Example.record(.controller, group: 1, lamp, data: [0x01, 0x02, 0x03])]),
      devices: [Example.device(lamp, engine: .i2, records: held)]
    )

    return try TransferPlanner.plan(from: backup, to: TransferTarget(address: await modem.address, records: []))

  }

  static func modem() async -> InMemoryModem {

    let modem: InMemoryModem = InMemoryModem()

    await modem.setEngine(.i2, of: lamp)
    await modem.setDatabase([0x0FFF: slotRecord(old, flags: [.inUse, .usedBefore, .fastFail]), 0x0FF7: AllLinkRecord(flags: [], group: AllLinkGroupNumber(rawValue: 0), address: InsteonAddress(0, 0, 0))], of: lamp)

    return modem

  }

  @Test func rewritesADevicesRecordToNameTheNewModemAndAddsTheModemsRecord() async throws {

    let modem = await Self.modem()
    let plan = try await Self.plan(modem)
    let report = await TransferExecutor(writer: ModemTransferWriter(modem: modem, plan: plan)).run(plan)

    #expect(report.isComplete)
    #expect(await modem.databases[Self.lamp]?[0x0FFF]?.address == (await modem.address))
    #expect(await modem.modemRecords.contains { $0.address == Self.lamp && $0.flags.contains(.controller) })

  }

  @Test func keepsTheFlagsADeviceMaintainsWhenItRewritesARecord() async throws {

    let modem = await Self.modem()
    let plan = try await Self.plan(modem)
    let before = try #require(await modem.databases[Self.lamp]?[0x0FFF])

    _ = await TransferExecutor(writer: ModemTransferWriter(modem: modem, plan: plan)).run(plan)

    let after = try #require(await modem.databases[Self.lamp]?[0x0FFF])

    #expect(after.flags == before.flags)
    #expect([after.data1, after.data2, after.data3] == [before.data1, before.data2, before.data3])

  }

  @Test func aSecondRunSendsNothingToTheDevice() async throws {

    let modem = await Self.modem()
    let plan = try await Self.plan(modem)

    _ = await TransferExecutor(writer: ModemTransferWriter(modem: modem, plan: plan)).run(plan)

    let second = await TransferExecutor(writer: ModemTransferWriter(modem: modem, plan: plan)).run(plan)

    #expect(second.isComplete)
    #expect(second.results.filter { $0.step.effect == .link }.allSatisfy { $0.outcome == .alreadyDone })

  }

  @Test func reportsADeviceThatRejectsTheModemAndLeavesItsRecordAlone() async throws {

    let modem = await Self.modem()
    let plan = try await Self.plan(modem)

    await modem.setUnlinked(Self.lamp)

    let report = await TransferExecutor(writer: ModemTransferWriter(modem: modem, plan: plan)).run(plan)

    #expect(report.failedDevices == [Self.lamp])
    #expect(await modem.databases[Self.lamp]?[0x0FFF]?.address == Self.old)

  }

}
