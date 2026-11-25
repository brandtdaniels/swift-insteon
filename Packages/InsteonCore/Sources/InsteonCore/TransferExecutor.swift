import Foundation
import InsteonProtocol

/// What a ``TransferExecutor`` reads and writes: the new modem's ALL-Link database and the
/// ALL-Link records of the devices.
///
/// Every method that throws means the modem or the device didn't answer, so it isn't known
/// whether a write landed. The executor never sends such a write again.
public protocol TransferWriting: Sendable {

  /// The records in use in the new modem's ALL-Link database.
  func modemRecords() async throws -> [BackupRecord]

  /// The record a device holds at a memory address, or `nil` if the slot holds none.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - memoryAddress: The slot's memory address.
  func deviceRecord(of device: InsteonAddress, at memoryAddress: UInt16) async throws -> BackupRecord?

  /// Adds a record to the new modem's ALL-Link database.
  func addToModem(_ record: BackupRecord) async throws

  /// Removes a record from the new modem's ALL-Link database.
  func removeFromModem(_ record: BackupRecord) async throws

  /// Writes a record into the slot of a device's ALL-Link database at the record's memory address.
  ///
  /// - Parameters:
  ///   - record: The record, with its memory address.
  ///   - device: The device.
  func write(_ record: BackupRecord, to device: InsteonAddress) async throws

}

/// What became of one step of a ``TransferPlan`` when it was carried out.
public enum TransferOutcome: String, Codable, Hashable, Sendable {

  /// The record read back as written.
  case written

  /// The record read back differently once and was written again, then read back as written.
  case writtenOnRetry

  /// The record was already as the step leaves it, so nothing was written.
  case alreadyDone

  /// The record read back differently after it was written twice.
  case notWritten

  /// The device or the modem didn't answer, so it isn't known whether the record was written.
  /// The step isn't sent again.
  case unanswered

  /// A record reads as neither the backup's nor the plan's, so something else changed it and it
  /// isn't written over.
  case changedSincePlanned

  /// An earlier step failed, so the step wasn't made.
  case notReached

  /// Whether the step did what it was meant to.
  public var isDone: Bool {

    switch self {
    case .written, .writtenOnRetry, .alreadyDone:
      true
    case .notWritten, .unanswered, .changedSincePlanned, .notReached:
      false
    }

  }

}

/// A step of a plan and what became of it.
public struct TransferStepResult: Hashable, Sendable {

  /// The step.
  public var step: TransferStep

  /// What became of it.
  public var outcome: TransferOutcome

}

/// What carrying out a ``TransferPlan`` did, step by step, in the plan's order.
public struct TransferReport: Hashable, Sendable {

  /// The new modem.
  public var newModem: InsteonAddress

  /// Each step with its outcome.
  public var results: [TransferStepResult]

  /// Whether every step is done.
  public var isComplete: Bool {

    results.allSatisfy { $0.outcome.isDone }

  }

  /// The devices with a step that failed, in the plan's order.
  public var failedDevices: [InsteonAddress] {

    var seen: Set<InsteonAddress> = []

    return results.compactMap { (result: TransferStepResult) -> InsteonAddress? in

      guard result.step.target != newModem, !result.outcome.isDone, result.outcome != .notReached else { return nil }

      return seen.insert(result.step.target).inserted ? result.step.target : nil

    }

  }

}

/// Carries out a ``TransferPlan``: adds the plan's records to the new modem, then rewrites each
/// device's records and reads them back.
///
/// Each step reads before it writes, so running a plan again, after an interruption or after it
/// finished, writes only what is still to write. A record that reads as neither the backup's nor
/// the plan's isn't written over. A write that wasn't confirmed isn't sent again.
///
/// ```swift
/// let report = await TransferExecutor(writer: writer).run(plan)
/// print(report.isComplete)
/// ```
public struct TransferExecutor: Sendable {

  private let writer: any TransferWriting
  private let keepGoing: Bool

  /// Creates an executor.
  ///
  /// - Parameters:
  ///   - writer: What it reads and writes through.
  ///   - keepGoing: Whether to go on to the next device after one fails. Defaults to `false`,
  ///     which stops at the first device that fails. A failed step on the new modem always stops.
  public init(writer: any TransferWriting, keepGoing: Bool = false) {

    self.writer = writer
    self.keepGoing = keepGoing

  }

  /// Carries out the plan.
  ///
  /// - Parameters:
  ///   - plan: The plan.
  ///   - onStep: Called after each step, in order, with its outcome, including a step that
  ///     wasn't reached.
  /// - Returns: Each step's outcome.
  public func run(_ plan: TransferPlan, onStep: (@Sendable (TransferStep, TransferOutcome) async -> Void)? = nil) async -> TransferReport {

    var results: [TransferStepResult] = []

    func record(_ step: TransferStep, _ outcome: TransferOutcome) async {

      results.append(TransferStepResult(step: step, outcome: outcome))

      await onStep?(step, outcome)

    }

    var isStopped: Bool = false

    for step in plan.modemSteps {

      guard !isStopped, !Task.isCancelled else {

        await record(step, .notReached)

        continue

      }

      let outcome: TransferOutcome = await carryOut(step, rewrites: [])

      await record(step, outcome)

      isStopped = !outcome.isDone

    }

    for device in plan.devices {

      var isDeviceStopped: Bool = isStopped
      let rewrites: [TransferStep] = device.steps.filter { $0.action == .rewriteRecord }

      for step in device.steps {

        guard !isDeviceStopped, !Task.isCancelled else {

          await record(step, .notReached)

          continue

        }

        let outcome: TransferOutcome = await carryOut(step, rewrites: rewrites)

        await record(step, outcome)

        isDeviceStopped = !outcome.isDone

      }

      if isDeviceStopped, !isStopped, !keepGoing {

        isStopped = true

      }

    }

    return TransferReport(newModem: plan.newModem, results: results)

  }

  // MARK: - Steps

  private func carryOut(_ step: TransferStep, rewrites: [TransferStep]) async -> TransferOutcome {

    do {

      switch step.action {
      case .addModemRecord:
        guard let record = step.record else { return .notWritten }

        return try await changeModem(contains: true, record) { try await writer.addToModem(record) }
      case .removeModemRecord:
        guard let record = step.record else { return .notWritten }

        return try await changeModem(contains: false, record) { try await writer.removeFromModem(record) }
      case .readDatabase:
        for rewrite in rewrites {

          let held: BackupRecord? = try await writer.deviceRecord(of: step.target, at: rewrite.record?.memoryAddress ?? 0)

          guard held == rewrite.replaces || held == rewrite.record else { return .changedSincePlanned }

        }

        return .alreadyDone
      case .rewriteRecord:
        return try await rewrite(step)
      case .readBack:
        for rewrite in rewrites {

          let held: BackupRecord? = try await writer.deviceRecord(of: step.target, at: rewrite.record?.memoryAddress ?? 0)

          guard held == rewrite.record else { return .notWritten }

        }

        return .alreadyDone
      }

    } catch {

      return .unanswered

    }

  }

  /// Makes the new modem hold the record, or not hold it, and reads to check.
  private func changeModem(contains wanted: Bool, _ record: BackupRecord, _ change: () async throws -> Void) async throws -> TransferOutcome {

    if try await writer.modemRecords().contains(record) == wanted { return .alreadyDone }

    try await change()

    if try await writer.modemRecords().contains(record) == wanted { return .written }

    try await change()

    return try await writer.modemRecords().contains(record) == wanted ? .writtenOnRetry : .notWritten

  }

  private func rewrite(_ step: TransferStep) async throws -> TransferOutcome {

    guard let record = step.record, let memoryAddress = record.memoryAddress else { return .notWritten }

    let held: BackupRecord? = try await writer.deviceRecord(of: step.target, at: memoryAddress)

    if held == record { return .alreadyDone }

    guard held == step.replaces else { return .changedSincePlanned }

    try await writer.write(record, to: step.target)

    if try await writer.deviceRecord(of: step.target, at: memoryAddress) == record { return .written }

    try await writer.write(record, to: step.target)

    return try await writer.deviceRecord(of: step.target, at: memoryAddress) == record ? .writtenOnRetry : .notWritten

  }

}
