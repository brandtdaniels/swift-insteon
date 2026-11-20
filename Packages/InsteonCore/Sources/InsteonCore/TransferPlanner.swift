import Foundation
import InsteonProtocol

/// Plans how a backup's devices move to a new modem. It's pure: it reads a backup and the new
/// modem's database and returns a ``TransferPlan``, and nothing it does reaches a modem or a
/// device.
///
/// Every device holds records that name its controller by the modem's address, and a new modem
/// has another address, so the plan swaps controllers:
///
/// - A record of a device's that names the old modem is rewritten in place to name the new
///   modem, with the same role, group and data bytes.
/// - The old modem's matching record for that device is added to the new modem, so the new
///   modem holds both halves of the link.
///
/// A device is rewritten from afar only when it runs i2, its ALL-Link database is in the backup
/// whole, and the backup holds the old modem's database. Any other device is re-linked by hand,
/// with the links to restore listed. A link the old modem or the device holds without the other
/// half is dead, so the plan leaves it as it is and says so. Links between devices, which name
/// neither modem, are never touched.
///
/// ```swift
/// let target = TransferTarget(address: newModemAddress, records: newModemRecords)
/// let plan = try TransferPlanner.plan(from: backup, to: target, existingLinks: .merge)
/// ```
public enum TransferPlanner {

  /// Makes the plan for a backup and a new modem.
  ///
  /// - Parameters:
  ///   - backup: The backup, whose checksum the caller has already checked.
  ///   - target: The new modem.
  ///   - existingLinks: What to do when the new modem already holds links. Defaults to
  ///     ``ExistingLinksChoice/refuse``.
  /// - Returns: The plan.
  /// - Throws: ``TransferPlanError``.
  public static func plan(from backup: HomeBackup, to target: TransferTarget, existingLinks choice: ExistingLinksChoice = .refuse) throws -> TransferPlan {

    let old: InsteonAddress? = backup.modem?.address

    guard old != target.address else {

      throw TransferPlanError.sameModem
    }

    guard !backup.devices.contains(where: { (device: BackupDevice) -> Bool in device.address == target.address }) else {

      throw TransferPlanError.targetIsInBackup
    }

    let present: [BackupRecord] = (target.records ?? []).filter(\.isInUse)

    if !present.isEmpty, choice == .refuse {

      throw TransferPlanError.existingLinks(count: present.count)

    }

    let handling: ExistingLinksHandling = target.records == nil ? .unread : (present.isEmpty ? .none : (choice == .replaceDatabase ? .replaceDatabase : .merge))
    let oldRecords: [BackupRecord]? = backup.modem?.allLinkDatabase?.filter(\.isInUse)

    let warnings: [String] = Self.warnings(for: handling, count: present.count, backup: backup, hasOldDatabase: oldRecords != nil)
    var modemAdds: [Key: BackupRecord] = [:]
    var modemFindings: [TransferFinding] = []
    var devices: [DeviceTransfer] = []
    var unchanged: [InsteonAddress] = []
    var manual: [ManualTransfer] = []

    for device in backup.devices {

      guard let old, let oldRecords else {

        manual.append(manualTransfer(device, reason: .noModemDatabase, oldRecords: []))

        continue

      }

      let held: [BackupRecord] = oldRecords.filter { (record: BackupRecord) -> Bool in record.address == device.address }

      guard let database = device.allLinkDatabase else {

        manual.append(manualTransfer(device, reason: .noDatabase, oldRecords: held))

        continue

      }

      guard database.isComplete, database.records.allSatisfy({ (record: BackupRecord) -> Bool in record.memoryAddress != nil }) else {

        manual.append(manualTransfer(device, reason: .incompleteDatabase, oldRecords: held))

        continue

      }

      let naming: [BackupRecord] = database.records.filter { (record: BackupRecord) -> Bool in record.isInUse && record.address == old }

      switch device.engine {
      case .i2?:
        break
      case .i1?, .i2cs?, nil:
        if naming.isEmpty, held.isEmpty {

          unchanged.append(device.address)

        } else {

          manual.append(manualTransfer(device, reason: reason(for: device.engine), oldRecords: held))

        }

        continue
      }

      var rewrites: [(replaces: BackupRecord, record: BackupRecord)] = []
      var findings: [TransferFinding] = []
      var seen: Set<Key> = []
      var paired: Set<Key> = []

      for record in naming {

        let key: Key = Key(record)

        guard seen.insert(key).inserted else {

          findings.append(TransferFinding(kind: .duplicateRecord, record: record, summary: "The record at \(BackupText.memory(record.memoryAddress ?? 0)) repeats an earlier record of the same link, so it's left as it is."))

          continue

        }

        // The old modem's half of the link: the opposite role, the same group, this device.
        let partner: BackupRecord? = held.first { (modemRecord: BackupRecord) -> Bool in
          modemRecord.role != record.role && modemRecord.group == record.group
        }

        guard let partner else {

          findings.append(TransferFinding(kind: .noMatchingModemRecord, record: record, summary: "The old modem holds no matching record, so the link is already dead and the record at \(BackupText.memory(record.memoryAddress ?? 0)) is left as it is."))

          continue

        }

        paired.insert(Key(partner))
        rewrites.append((record, BackupRecord(state: .inUse, role: record.role, group: record.group, address: target.address, data: record.data, memoryAddress: record.memoryAddress)))

        let added: BackupRecord = BackupRecord(state: .inUse, role: partner.role, group: partner.group, address: device.address, data: partner.data)

        modemAdds[Key(added)] = added

      }

      var counted: Set<Key> = []

      for modemRecord in held {

        let key: Key = Key(modemRecord)

        if paired.contains(key) {

          if !counted.insert(key).inserted {

            modemFindings.append(TransferFinding(kind: .duplicateModemRecord, record: modemRecord, summary: "The old modem holds this link more than once, so it's added to the new modem once."))

          }

        } else {

          modemFindings.append(TransferFinding(kind: .noMatchingDeviceRecord, record: modemRecord, summary: "The device holds no matching record, so the old modem's link is already dead and isn't copied."))

        }

      }

      guard !rewrites.isEmpty else {

        if findings.isEmpty {

          unchanged.append(device.address)

        } else {

          devices.append(DeviceTransfer(address: device.address, name: device.name, type: device.type, engine: .i2, steps: [], findings: findings))

        }

        continue

      }

      let ordered = rewrites.sorted { (first: (replaces: BackupRecord, record: BackupRecord), second: (replaces: BackupRecord, record: BackupRecord)) -> Bool in (first.record.memoryAddress ?? 0) < (second.record.memoryAddress ?? 0) }
      var steps: [TransferStep] = [
        TransferStep(number: 0, effect: .readOnly, action: .readDatabase, target: device.address, record: nil, replaces: nil, summary: "Read the ALL-Link database of \(device.address) and check its delta is still \(BackupText.byte(database.delta)).")
      ]

      for rewrite in ordered {

        steps.append(TransferStep(number: 0, effect: .link, action: .rewriteRecord, target: device.address, record: rewrite.record, replaces: rewrite.replaces, summary: "Rewrite the record at \(BackupText.memory(rewrite.record.memoryAddress ?? 0)) of \(device.address) to \(Self.describe(rewrite.record)), replacing the one naming \(old)."))

      }

      steps.append(TransferStep(number: 0, effect: .readOnly, action: .readBack, target: device.address, record: nil, replaces: nil, summary: "Read the \(ordered.count == 1 ? "record" : "\(ordered.count) records") of \(device.address) back and check \(ordered.count == 1 ? "it" : "they") read as written."))

      devices.append(DeviceTransfer(address: device.address, name: device.name, type: device.type, engine: .i2, steps: steps, findings: findings))

    }

    // Records of the old modem for an address that isn't a device in the backup.
    let known: Set<InsteonAddress> = Set(backup.devices.map(\.address))

    for record in oldRecords ?? [] where !known.contains(record.address) && record.address != old {

      modemFindings.append(TransferFinding(kind: .recordForUnknownDevice, record: record, summary: "The old modem holds a record for \(record.address), which isn't a device in the backup, so it isn't copied."))

    }

    let modemSteps: [TransferStep] = modemSteps(adds: modemAdds, present: present, handling: handling, target: target.address, findings: &modemFindings)

    var plan: TransferPlan = TransferPlan(
      backupChecksum: backup.checksum,
      oldModem: old,
      newModem: target.address,
      existingLinks: handling,
      existingLinkCount: target.records == nil ? nil : present.count,
      warnings: warnings,
      modemSteps: modemSteps,
      modemFindings: modemFindings.sorted(by: Self.ordered),
      devices: devices,
      unchangedDevices: unchanged,
      manual: manual
    )

    // The new modem's steps come first, then each device's, numbered in that order.
    var number: Int = 0

    func numbered(_ step: TransferStep) -> TransferStep {

      number += 1

      var step: TransferStep = step

      step.number = number

      return step

    }

    plan.modemSteps = plan.modemSteps.map(numbered)
    plan.devices = plan.devices.map { (device: DeviceTransfer) -> DeviceTransfer in

      var device: DeviceTransfer = device

      device.steps = device.steps.map(numbered)
      device.findings.sort(by: Self.ordered)

      return device

    }

    plan.manual = plan.manual.enumerated().map { (index: Int, item: ManualTransfer) -> ManualTransfer in

      var item: ManualTransfer = item

      item.order = index + 1

      return item

    }

    return plan

  }

  // MARK: - The new modem's steps

  private static func modemSteps(
    adds: [Key: BackupRecord],
    present: [BackupRecord],
    handling: ExistingLinksHandling,
    target: InsteonAddress,
    findings: inout [TransferFinding]
  ) -> [TransferStep] {

    var steps: [TransferStep] = []

    if handling == .replaceDatabase {

      for record in present.sorted(by: Self.recordOrder) {

        steps.append(TransferStep(number: 0, effect: .destructive, action: .removeModemRecord, target: target, record: record, replaces: nil, summary: "Remove the new modem's record: \(describe(record))."))

      }

    }

    for (key, record) in adds.sorted(by: { (first: (key: Key, value: BackupRecord), second: (key: Key, value: BackupRecord)) -> Bool in recordOrder(first.value, second.value) }) {

      if handling == .merge, let existing = present.first(where: { Key($0) == key }) {

        let sameData: Bool = existing.data == record.data

        findings.append(TransferFinding(
          kind: sameData ? .alreadyInPlace : .conflictingModemRecord,
          record: record,
          summary: sameData ? "The new modem already holds this link, so nothing is added." : "The new modem already holds this link with data \(BackupText.pairs(existing.data)), and keeps it."
        ))

        continue

      }

      steps.append(TransferStep(number: 0, effect: .link, action: .addModemRecord, target: target, record: record, replaces: nil, summary: "Add to the new modem: \(describe(record))."))

    }

    return steps

  }

  // MARK: - Manual devices

  private static func manualTransfer(_ device: BackupDevice, reason: ManualTransferReason, oldRecords: [BackupRecord]) -> ManualTransfer {

    ManualTransfer(
      order: 0,
      address: device.address,
      name: device.name,
      type: device.type,
      reason: reason,
      linksToRestore: oldRecords.sorted(by: recordOrder),
      steps: [
        "On the new modem, press and hold the SET button until it beeps, which puts it in linking mode.",
        "On \(device.address), press and hold its SET button until it beeps or its light blinks, which links the two.",
        "Repeat for each link listed, using the device's own way to link a group."
      ]
    )

  }

  private static func reason(for engine: BackupEngine?) -> ManualTransferReason {

    switch engine {
    case .i1?:
      .noRemoteWrites
    case .i2cs?:
      .rejectsUntilLinked
    case .i2?, nil:
      .engineUnknown
    }

  }

  // MARK: - Text and order

  private static func warnings(for handling: ExistingLinksHandling, count: Int, backup: HomeBackup, hasOldDatabase: Bool) -> [String] {

    var warnings: [String] = []

    switch handling {
    case .none:
      break
    case .merge:
      warnings.append("The new modem already holds \(count) \(count == 1 ? "link" : "links"). Merging keeps them and adds the backup's. A link both hold with different data bytes stays as the new modem has it. Nothing is removed.")
    case .replaceDatabase:
      warnings.append("The new modem already holds \(count) \(count == 1 ? "link" : "links"). Replacing its database removes each one first, which is destructive: a device linked only to the new modem stops answering it until the device is linked again.")
    case .unread:
      warnings.append("The new modem's ALL-Link database wasn't read, so the plan can't tell whether it holds links and assumes it holds none.")
    }

    if !hasOldDatabase {

      warnings.append(backup.source == .hubPro
        ? "The backup is a Hub Pro's device list, which holds no ALL-Link databases, so every device is re-linked by hand."
        : "The backup holds no ALL-Link database of the old modem, so no device's records can be matched to it and every device is re-linked by hand.")

    }

    return warnings

  }

  private static func describe(_ record: BackupRecord) -> String {

    "\(record.role.rawValue), group \(record.group), \(record.address), data \(BackupText.pairs(record.data))"

  }

  private static func recordOrder(_ first: BackupRecord, _ second: BackupRecord) -> Bool {

    let left: [UInt8] = first.address.bytes + [first.group, first.role == .controller ? 0 : 1]
    let right: [UInt8] = second.address.bytes + [second.group, second.role == .controller ? 0 : 1]

    return left.lexicographicallyPrecedes(right)

  }

  private static func ordered(_ first: TransferFinding, _ second: TransferFinding) -> Bool {

    if first.record.memoryAddress != second.record.memoryAddress {

      return (first.record.memoryAddress ?? 0) < (second.record.memoryAddress ?? 0)

    }

    if first.kind != second.kind {

      return first.kind.rawValue < second.kind.rawValue

    }

    return recordOrder(first.record, second.record)

  }

  /// A link as the database keeps it: the role, the group and the other device.
  private struct Key: Hashable {

    let role: BackupRecordRole
    let group: UInt8
    let address: InsteonAddress

    init(_ record: BackupRecord) {

      self.role = record.role
      self.group = record.group
      self.address = record.address

    }

  }

}
