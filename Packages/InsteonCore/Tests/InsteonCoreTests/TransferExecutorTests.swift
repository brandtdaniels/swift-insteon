import Foundation
import InsteonProtocol
import Testing
@testable import InsteonCore

/// A new modem and the devices of a home, as the executor sees them, with faults to inject.
final class ScriptedTransferWriter: TransferWriting, @unchecked Sendable {

  struct Silent: Error {}

  private let lock: NSLock = NSLock()
  private var modem: [BackupRecord]
  private var slots: [InsteonAddress: [UInt16: BackupRecord]]
  private var silentDevices: Set<InsteonAddress> = []
  private var lostWrites: [InsteonAddress: Int] = [:]
  private var unconfirmedDevices: Set<InsteonAddress> = []
  private var drifts: [InsteonAddress: (after: Int, record: BackupRecord, memory: UInt16)] = [:]
  private var reads: [InsteonAddress: Int] = [:]
  private var isModemSilent: Bool = false
  private(set) var deviceWrites: [InsteonAddress: Int] = [:]
  private(set) var modemAdds: Int = 0
  private(set) var modemRemoves: Int = 0

  init(modem: [BackupRecord] = [], slots: [InsteonAddress: [UInt16: BackupRecord]]) {

    self.modem = modem
    self.slots = slots

  }

  func silence(_ device: InsteonAddress) {

    lock.withLock { _ = silentDevices.insert(device) }

  }

  /// Makes a write to the device land and then fail to be confirmed, as a lost acknowledgment does.
  func failToConfirmWrites(to device: InsteonAddress) {

    lock.withLock { _ = unconfirmedDevices.insert(device) }

  }

  /// Makes a slot of the device change on its own once it has been read `reads` times, as another
  /// program writing to it would.
  func drift(_ device: InsteonAddress, afterReads count: Int, to record: BackupRecord, at memory: UInt16) {

    lock.withLock { drifts[device] = (count, record, memory) }

  }

  func silenceModem() {

    lock.withLock { isModemSilent = true }

  }

  /// Drops the next `count` writes to the device, as a device that acknowledges and keeps nothing does.
  func lose(_ count: Int, writesTo device: InsteonAddress) {

    lock.withLock { lostWrites[device] = count }

  }

  func hold(_ record: BackupRecord, at memory: UInt16, of device: InsteonAddress) {

    lock.withLock { slots[device, default: [:]][memory] = record }

  }

  var modemRecordsNow: [BackupRecord] { lock.withLock { modem } }

  func slot(_ memory: UInt16, of device: InsteonAddress) -> BackupRecord? {

    lock.withLock { slots[device]?[memory] }

  }

  func modemRecords() async throws -> [BackupRecord] {

    try lock.withLock {

      guard !isModemSilent else { throw Silent() }

      return modem

    }

  }

  func deviceRecord(of device: InsteonAddress, at memoryAddress: UInt16) async throws -> BackupRecord? {

    try lock.withLock {

      guard !silentDevices.contains(device) else { throw Silent() }

      let held = slots[device]?[memoryAddress]

      reads[device, default: 0] += 1

      if let drift = drifts[device], reads[device, default: 0] > drift.after {

        slots[device, default: [:]][drift.memory] = drift.record

        return memoryAddress == drift.memory ? drift.record : held

      }

      return held

    }

  }

  func addToModem(_ record: BackupRecord) async throws {

    try lock.withLock {

      guard !isModemSilent else { throw Silent() }

      modemAdds += 1
      modem.append(record)

    }

  }

  func removeFromModem(_ record: BackupRecord) async throws {

    try lock.withLock {

      guard !isModemSilent else { throw Silent() }

      modemRemoves += 1
      modem.removeAll { $0 == record }

    }

  }

  func write(_ record: BackupRecord, to device: InsteonAddress) async throws {

    try lock.withLock {

      guard !silentDevices.contains(device) else { throw Silent() }

      deviceWrites[device, default: 0] += 1

      if let remaining = lostWrites[device], remaining > 0 {

        lostWrites[device] = remaining - 1

        return

      }

      slots[device, default: [:]][record.memoryAddress ?? 0] = record

      if unconfirmedDevices.contains(device) { throw Silent() }

    }

  }

}

@Suite(.timeLimit(.minutes(1)))
struct TransferExecutorTests {

  typealias Example = BackupExample

  static let old = Example.oldModem
  static let new = Example.newModem

  /// The record a device holds before the transfer, naming the old modem.
  static func before(_ memory: UInt16 = 0x0FFF, group: UInt8 = 1) -> BackupRecord {

    Example.record(.responder, group: group, old, data: [0xFF, 0x1F, 0x01], memory: memory)

  }

  /// The record the transfer leaves, naming the new modem.
  static func after(_ memory: UInt16 = 0x0FFF, group: UInt8 = 1) -> BackupRecord {

    Example.record(.responder, group: group, new, data: [0xFF, 0x1F, 0x01], memory: memory)

  }

  static func controls(_ device: InsteonAddress, group: UInt8 = 1) -> BackupRecord {

    Example.record(.controller, group: group, device, data: [0x01, 0x02, 0x03])

  }

  /// A home of two lamps, each linked to the old modem in group 1, moved to the new modem.
  static func home() throws -> (plan: TransferPlan, writer: ScriptedTransferWriter) {

    let devices: [BackupDevice] = [
      Example.device(Example.lamp, records: [before(), Example.end(0x0FF7)]),
      Example.device(Example.plug, records: [before(), Example.end(0x0FF7)])
    ]
    let backup: HomeBackup = Example.backup(devices, modemRecords: [controls(Example.lamp), controls(Example.plug)])
    let plan: TransferPlan = try TransferPlanner.plan(from: backup, to: TransferTarget(address: new, records: []))
    let writer: ScriptedTransferWriter = ScriptedTransferWriter(slots: [Example.lamp: [0x0FFF: before()], Example.plug: [0x0FFF: before()]])

    return (plan, writer)

  }

  // MARK: - Applying

  @Test func addsTheModemsRecordsThenRewritesAndReadsBackEachDevice() async throws {

    let (plan, writer) = try Self.home()
    let report = await TransferExecutor(writer: writer).run(plan)

    #expect(report.isComplete)
    #expect(report.results.map(\.step) == plan.steps)
    #expect(report.results.allSatisfy { $0.outcome.isDone })
    #expect(Set(writer.modemRecordsNow) == [Self.controls(Example.lamp), Self.controls(Example.plug)])
    #expect(writer.slot(0x0FFF, of: Example.lamp) == Self.after())
    #expect(writer.slot(0x0FFF, of: Example.plug) == Self.after())

  }

  @Test func reportsEachStepToTheCallerInOrderAsItIsMade() async throws {

    let (plan, writer) = try Self.home()
    let seen = StepLog()

    _ = await TransferExecutor(writer: writer).run(plan) { step, outcome in await seen.add(step.number, outcome) }

    #expect(await seen.numbers == plan.steps.map(\.number))

  }

  @Test func aSecondRunWritesNothingAndSaysEverythingWasAlreadyDone() async throws {

    let (plan, writer) = try Self.home()

    _ = await TransferExecutor(writer: writer).run(plan)

    let writes = writer.deviceWrites
    let adds = writer.modemAdds
    let second = await TransferExecutor(writer: writer).run(plan)

    #expect(second.isComplete)
    #expect(writer.deviceWrites == writes)
    #expect(writer.modemAdds == adds)
    #expect(second.results.filter { $0.step.effect == .link }.allSatisfy { $0.outcome == .alreadyDone })

  }

  @Test func resumesAnInterruptedRunByWritingOnlyWhatIsStillToWrite() async throws {

    let (plan, writer) = try Self.home()

    // The lamp was rewritten and the modem has its record, then the power went.
    writer.hold(Self.after(), at: 0x0FFF, of: Example.lamp)
    try await writer.addToModem(Self.controls(Example.lamp))

    let report = await TransferExecutor(writer: writer).run(plan)

    #expect(report.isComplete)
    #expect(writer.deviceWrites[Example.lamp] == nil)
    #expect(writer.deviceWrites[Example.plug] == 1)
    #expect(writer.modemRecordsNow.filter { $0 == Self.controls(Example.lamp) }.count == 1)

  }

  // MARK: - A device that isn't as the plan read it

  @Test func leavesADeviceAloneWhoseRecordReadsAsNeitherTheBackupsNorThePlans() async throws {

    let (plan, writer) = try Self.home()
    let other: BackupRecord = Example.record(.responder, group: 9, Example.outlet, memory: 0x0FFF)

    writer.hold(other, at: 0x0FFF, of: Example.lamp)

    let report = await TransferExecutor(writer: writer, keepGoing: true).run(plan)

    #expect(!report.isComplete)
    #expect(report.failedDevices == [Example.lamp])
    #expect(writer.deviceWrites[Example.lamp] == nil)
    #expect(writer.slot(0x0FFF, of: Example.lamp) == other)
    #expect(writer.slot(0x0FFF, of: Example.plug) == Self.after())

  }

  @Test func doesNotWriteOverARecordThatChangesAfterItWasChecked() async throws {

    let (plan, writer) = try Self.home()
    let other: BackupRecord = Example.record(.responder, group: 9, Example.outlet, memory: 0x0FFF)

    // The first read is the plan's check of the database; the change comes before the rewrite reads.
    writer.drift(Example.lamp, afterReads: 1, to: other, at: 0x0FFF)

    let report = await TransferExecutor(writer: writer, keepGoing: true).run(plan)
    let rewrite = try #require(report.results.first { $0.step.target == Example.lamp && $0.step.action == .rewriteRecord })

    #expect(rewrite.outcome == .changedSincePlanned)
    #expect(writer.deviceWrites[Example.lamp] == nil)
    #expect(writer.slot(0x0FFF, of: Example.lamp) == other)

  }

  // MARK: - Stopping

  @Test func stopsAtTheFirstDeviceThatFailsUnlessToldToKeepGoing() async throws {

    let (plan, writer) = try Self.home()

    writer.silence(Example.lamp)

    let report = await TransferExecutor(writer: writer).run(plan)

    #expect(report.failedDevices == [Example.lamp])
    #expect(writer.slot(0x0FFF, of: Example.plug) == Self.before())
    #expect(report.results.filter { $0.step.target == Example.plug }.allSatisfy { $0.outcome == .notReached })

  }

  @Test func goesOnToTheNextDeviceWhenToldToKeepGoing() async throws {

    let (plan, writer) = try Self.home()

    writer.silence(Example.lamp)

    let report = await TransferExecutor(writer: writer, keepGoing: true).run(plan)

    #expect(report.failedDevices == [Example.lamp])
    #expect(writer.slot(0x0FFF, of: Example.plug) == Self.after())

  }

  @Test func neverSendsAWriteAgainThatMayHaveLanded() async throws {

    let (plan, writer) = try Self.home()

    // The write lands, but its acknowledgment is lost.
    writer.failToConfirmWrites(to: Example.lamp)

    let report = await TransferExecutor(writer: writer).run(plan)
    let rewrite = try #require(report.results.first { $0.step.target == Example.lamp && $0.step.action == .rewriteRecord })

    #expect(rewrite.outcome == .unanswered)
    #expect(writer.deviceWrites[Example.lamp] == 1)

  }

  @Test func writesARecordOnceMoreWhenItReadsBackDifferentlyThenSaysSo() async throws {

    let (plan, writer) = try Self.home()

    writer.lose(1, writesTo: Example.lamp)

    let report = await TransferExecutor(writer: writer).run(plan)
    let rewrite = try #require(report.results.first { $0.step.target == Example.lamp && $0.step.action == .rewriteRecord })

    #expect(rewrite.outcome == .writtenOnRetry)
    #expect(report.isComplete)
    #expect(writer.deviceWrites[Example.lamp] == 2)

  }

  @Test func givesUpOnARecordThatReadsBackDifferentlyTwice() async throws {

    let (plan, writer) = try Self.home()

    writer.lose(5, writesTo: Example.lamp)

    let report = await TransferExecutor(writer: writer).run(plan)
    let rewrite = try #require(report.results.first { $0.step.target == Example.lamp && $0.step.action == .rewriteRecord })

    #expect(rewrite.outcome == .notWritten)
    #expect(writer.deviceWrites[Example.lamp] == 2)
    #expect(!report.isComplete)

  }

  @Test func touchesNoDeviceWhenTheNewModemDoesNotAnswer() async throws {

    let (plan, writer) = try Self.home()

    writer.silenceModem()

    let report = await TransferExecutor(writer: writer, keepGoing: true).run(plan)

    #expect(!report.isComplete)
    #expect(writer.deviceWrites.isEmpty)
    #expect(report.results.filter { $0.step.target != Self.new }.allSatisfy { $0.outcome == .notReached })

  }

  @Test func removesTheModemsOwnRecordsWhenThePlanReplacesItsDatabase() async throws {

    let devices: [BackupDevice] = [Example.device(Example.lamp, records: [Self.before(), Example.end(0x0FF7)])]
    let backup: HomeBackup = Example.backup(devices, modemRecords: [Self.controls(Example.lamp)])
    let leftover: BackupRecord = Example.record(.controller, group: 4, Example.outlet, data: [0x00, 0x00, 0x00])
    let plan: TransferPlan = try TransferPlanner.plan(from: backup, to: TransferTarget(address: Self.new, records: [leftover]), existingLinks: .replaceDatabase)
    let writer: ScriptedTransferWriter = ScriptedTransferWriter(modem: [leftover], slots: [Example.lamp: [0x0FFF: Self.before()]])
    let report = await TransferExecutor(writer: writer).run(plan)

    #expect(report.isComplete)
    #expect(writer.modemRecordsNow == [Self.controls(Example.lamp)])
    #expect(writer.modemRemoves == 1)

  }

}

/// The steps a run reported, in order.
actor StepLog {

  private(set) var numbers: [Int] = []

  func add(_ number: Int, _ outcome: TransferOutcome) {

    numbers.append(number)

  }

}
