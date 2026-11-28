import InsteonLinking
import InsteonModem
import InsteonProtocol

extension DeviceLinkingCoordinator {

  /// Carries out a scene membership plan once the consent names it, and sends nothing without.
  ///
  /// The consent is judged before any message is sent: it must agree to the writes and name the plan's
  /// fingerprint, and the plan must have steps and no refusal. Then the modem's database and the database of each
  /// device a step writes to are read from the devices, never from a copy the network holds, and nothing is
  /// written unless every one is as the plan read it. A step is never allowed to write into a slot that holds a
  /// record in use, as the planner never plans one, and a slot that changed since it was read isn't written.
  ///
  /// Each step is then made in order and read back, through the same writes as
  /// ``apply(_:)`` makes for a link: a device's record is written with Read/Write ALL-Link Database (`0x2F`)
  /// and read back from its slot, a record that marks the end of the database is written into the slot below
  /// before the end's slot is, and a modem's record is added or deleted with Manage ALL-Link Record (`0x6F`)
  /// and its records for the device in the group read back. A step that reads back differently is made once more,
  /// and only then. When it still reads back differently, or a device or the modem doesn't answer or rejects it,
  /// no step after it is made. Nothing is rolled back: the steps made before the failure stay written, and the
  /// result says which they are. Last, the modem's database and each device's are read again and compared with what
  /// the steps that were made should have left; every other record is expected unchanged.
  ///
  /// Nothing else is sent: no operating flag is read or written, no device is put into linking mode, and no
  /// command is sent to a member. Afterward, the network forgets its copies of the databases of the devices and the
  /// modem, so they're read again when next needed.
  ///
  /// - Parameters:
  ///   - plan: The plan.
  ///   - consent: What the client granted.
  /// - Returns: Each step's outcome and what reading the databases again found.
  /// - Throws: ``SceneMembershipRefusal`` when the plan or the consent can't be carried out or a database
  ///   isn't as the plan read it, before anything is written. The modem's error when a database can't be read
  ///   before the first write. ``SceneMembershipInterrupted`` when the steps stop partway for anything but a device's
  ///   own timeout or rejection, such as the modem's error, a slot that changed before it was written, or
  ///   `CancellationError`: it carries the outcome of each step, and what reading the databases again found when
  ///   they could be read. A device's own timeouts and rejections don't throw; a step's outcome says so.
  public func apply(_ plan: SceneMembershipPlan, consent: DatabaseLinkConsent) async throws -> SceneMembershipResult {

    guard plan.isApplicable else {

      throw SceneMembershipRefusal.notApplicable

    }

    guard consent.writeLinkRecords else {

      throw SceneMembershipRefusal.consentRequired

    }

    guard consent.readFingerprint == plan.fingerprint else {

      throw SceneMembershipRefusal.consentMismatch

    }

    let touched: [InsteonAddress] = Self.devices(touchedBy: plan)

    do {

      let result: SceneMembershipResult = try await inTurn(changing: nil) { () async throws -> SceneMembershipResult in

        try await self.applyAfterConsent(plan)

      }

      await forgetDatabases(of: touched, answered: true)

      return result

    } catch let interrupted as SceneMembershipInterrupted {

      await forgetDatabases(of: touched, answered: false)

      throw interrupted

    }

  }

  /// The devices the plan writes to, each once, in the order of their first step.
  static func devices(writtenBy plan: SceneMembershipPlan) -> [InsteonAddress] {

    var devices: [InsteonAddress] = []

    for step in plan.steps {

      if case let .device(address) = step.endpoint, !devices.contains(address) {

        devices.append(address)

      }

    }

    return devices

  }

  /// The devices the plan writes to or names in a record of the modem's, each once.
  static func devices(touchedBy plan: SceneMembershipPlan) -> [InsteonAddress] {

    var devices: [InsteonAddress] = devices(writtenBy: plan)

    for step in plan.steps where step.endpoint == .modem && !devices.contains(step.record.address) {

      devices.append(step.record.address)

    }

    return devices

  }

  /// Forgets the network's copies of the databases of the devices and the modem, which the steps changed or
  /// may have.
  private func forgetDatabases(of devices: [InsteonAddress], answered: Bool) async {

    for device in devices {

      await network.recordLinkChange(of: device, answered: answered)

    }

  }

  // MARK: - Reading before the writes

  /// What the hardware holds before the first step: each device's records by slot, and the modem's records in use.
  private struct Reading: Sendable {

    var devices: [InsteonAddress: [AllLinkRecordResponse]] = [:]

    var modemRecords: [AllLinkRecord] = []

  }

  /// Whether a database read from a device is the one a plan was made from, record for record.
  private static func isPlanned(_ responses: [AllLinkRecordResponse], _ planned: [BackupRecord]) -> Bool {

    responses.count == planned.count && zip(responses, planned).allSatisfy { (pair: (AllLinkRecordResponse, BackupRecord)) -> Bool in

      BackupRecord(LinkRecord(pair.0)) == pair.1

    }

  }

  /// Whether the modem's records in use are those a plan was made from, in any order.
  private static func isPlanned(_ records: [AllLinkRecord], _ planned: [BackupRecord]) -> Bool {

    let found: [BackupRecord] = records.filter { (record: AllLinkRecord) -> Bool in record.flags.contains(.inUse) }.map { (record: AllLinkRecord) -> BackupRecord in BackupRecord(LinkRecord(record)) }

    return found.count == planned.count && found.allSatisfy { (record: BackupRecord) -> Bool in

      found.filter { (other: BackupRecord) -> Bool in other == record }.count == planned.filter { (other: BackupRecord) -> Bool in other == record }.count

    }

  }

  /// Reads the modem's database and each device's from the devices, and refuses when any isn't as the plan read it.
  private func readBeforeWriting(_ plan: SceneMembershipPlan) async throws -> Reading {

    let modem: any LinkingModem = network.modem
    var reading: Reading = Reading()

    reading.modemRecords = try await modem.allLinkRecords()

    guard Self.isPlanned(reading.modemRecords, plan.modemRead) else {

      throw SceneMembershipRefusal.planStale(nil)

    }

    for device in Self.devices(writtenBy: plan) {

      let responses: [AllLinkRecordResponse] = try await modem.readAllLinkDatabase(of: device, timeout: Modem.defaultExtendedRequestTimeout)

      // A database that doesn't read whole, or read otherwise than the plan did, isn't the one the plan was made from.
      guard
        responses.allSatisfy(\.hasIntactChecksum),
        let planned = plan.deviceReads[device],
        Self.isPlanned(responses, planned)
      else {

        throw SceneMembershipRefusal.planStale(device)

      }

      reading.devices[device] = responses

    }

    // No step may write a slot that holds a record in use, or clear one that holds none.
    for step in plan.steps {

      guard case let .device(device) = step.endpoint, let address = step.record.memoryAddress else {

        continue

      }

      let held: AllLinkRecord? = reading.devices[device]?.first { (response: AllLinkRecordResponse) -> Bool in response.address == address }?.record
      let isHeldInUse: Bool = held?.flags.contains(.inUse) ?? false

      switch step.kind {
      case .addDeviceRecord, .markEndOfDatabase, .updateDeviceRecord:
        // An update rewrites a record in use, which a plan can't carry until it has been tried on hardware.
        if isHeldInUse {

          throw SceneMembershipRefusal.wouldOverwriteRecord(device)

        }
      case .removeDeviceRecord:
        if !isHeldInUse {

          throw SceneMembershipRefusal.wouldOverwriteRecord(device)

        }
      case .addModemRecord, .removeModemRecord:
        break
      }

    }

    return reading

  }

  // MARK: - Writing

  /// The step as the coordinator writes it.
  private static func linkStep(_ step: SceneMembershipStep, reading: Reading) -> DatabaseLinkStep {

    let address: UInt16? = step.record.memoryAddress

    switch step.kind {
    case .markEndOfDatabase:
      return DatabaseLinkStep(kind: .markEndOfDatabase, written: .endOfDatabase, memoryAddress: address)
    case .addDeviceRecord, .updateDeviceRecord:
      return DatabaseLinkStep(kind: .addDeviceRecord, written: AllLinkRecord(flags: .linked(isController: step.record.isController), group: step.record.group, address: step.record.address, data1: step.record.data[0], data2: step.record.data[1], data3: step.record.data[2]), memoryAddress: address)
    case .removeDeviceRecord:
      // The record as the device held it, with its in-use bit cleared, so every other flag stays.
      var cleared: AllLinkRecord = step.record.allLinkRecord

      if case let .device(device) = step.endpoint, let held = reading.devices[device]?.first(where: { (response: AllLinkRecordResponse) -> Bool in response.address == address })?.record {

        cleared = held
        cleared.flags.remove(.inUse)

      }

      return DatabaseLinkStep(kind: .removeDeviceRecord, written: cleared, memoryAddress: address)
    case .addModemRecord:
      return DatabaseLinkStep(kind: .addModemRecord, written: AllLinkRecord(flags: .linked(isController: true), group: step.record.group, address: step.record.address, data1: step.record.data[0], data2: step.record.data[1], data3: step.record.data[2]), memoryAddress: nil)
    case .removeModemRecord:
      var deleted: AllLinkRecord = step.record.allLinkRecord
      deleted.flags.remove(.inUse)

      return DatabaseLinkStep(kind: .removeModemRecord, written: deleted, memoryAddress: nil)
    }

  }

  private func applyAfterConsent(_ plan: SceneMembershipPlan) async throws -> SceneMembershipResult {

    let reading: Reading = try await readBeforeWriting(plan)
    let engines: [InsteonAddress: InsteonEngine] = Dictionary(plan.devices.compactMap { (device: SceneMembershipDevice) -> (InsteonAddress, InsteonEngine)? in device.engine.map { (device.address, $0) } }, uniquingKeysWith: { (first: InsteonEngine, _: InsteonEngine) -> InsteonEngine in first })
    var results: [SceneMembershipResult.StepResult] = []
    var isStopped: Bool = false
    var interruption: (any Error)?
    // What each slot of each device's database holds, as read and as written since.
    var slots: [InsteonAddress: [UInt16: AllLinkRecord]] = reading.devices.mapValues { (responses: [AllLinkRecordResponse]) -> [UInt16: AllLinkRecord] in Self.slots(of: responses) }

    for step in plan.steps {

      // A request canceled between two steps makes no step after it.
      if !isStopped, Task.isCancelled {

        interruption = CancellationError()
        isStopped = true

      }

      guard !isStopped else {

        results.append(SceneMembershipResult.StepResult(step: step, outcome: .notReached))

        continue

      }

      do {

        let outcome: DatabaseLinkStepOutcome
        let linkStep: DatabaseLinkStep = Self.linkStep(step, reading: reading)

        if case let .device(device) = step.endpoint, let address = step.record.memoryAddress {

          let engine: InsteonEngine = engines[device] ?? .i2cs

          if let expected = slots[device]?[address] {

            let holds: Bool

            do {

              holds = try await slotHolds(expected, at: address, of: device, engine: engine)

            } catch where Self.isDeviceProblem(error) {

              // Nothing was written for this step: only its slot was read, so it was not reached.
              results.append(SceneMembershipResult.StepResult(step: step, outcome: .notReached))
              interruption = error
              isStopped = true

              continue

            }

            guard holds else {

              // Something else wrote the slot since it was read, so it isn't written over.
              results.append(SceneMembershipResult.StepResult(step: step, outcome: .notReached))
              interruption = SceneMembershipRefusal.planStale(device)
              isStopped = true

              continue

            }

          }

          // An i2CS device rejects the modem once its last record of the modem is gone.
          outcome = try await writeDeviceRecord(linkStep, of: device, engine: engine, mayBecomeUnreadable: step.risks.contains(.rejectsModemOnceUnlinked))

          if outcome.isDone {

            slots[device, default: [:]][address] = linkStep.written

          }

        } else {

          outcome = try await writeModemRecord(linkStep, of: step.record.address)

        }

        results.append(SceneMembershipResult.StepResult(step: step, outcome: outcome))
        isStopped = !outcome.isDone

      } catch {

        // It isn't known whether the step took; the steps after it aren't made.
        results.append(SceneMembershipResult.StepResult(step: step, outcome: .unanswered))
        interruption = error
        isStopped = true

      }

    }

    var verification: Verification = Verification()

    // Steps skipped for a cancellation read nothing more, so the databases aren't read again.
    if !(interruption is CancellationError) {

      verification = await verify(plan, reading: reading, results: results)
      interruption = interruption ?? verification.failure

    }

    let result = SceneMembershipResult(plan: plan, steps: results, mismatches: verification.mismatches, deviceChecks: verification.deviceChecks, isModemChecked: verification.isModemChecked)

    if let interruption {

      throw SceneMembershipInterrupted(result: result, cause: interruption)

    }

    return result

  }

  // MARK: - Reading after the writes

  /// What reading the databases again found. A read that fails ends the reading and is kept in `failure`, with
  /// everything found before it.
  private struct Verification: Sendable {

    var mismatches: [SceneMembershipResult.Mismatch] = []

    var deviceChecks: [InsteonAddress: DatabaseLinkResult.DeviceCheck] = [:]

    var isModemChecked: Bool = false

    var failure: (any Error)?

  }

  /// Reads the modem's database and each device's again and compares them with what the steps that were made
  /// should have left.
  private func verify(_ plan: SceneMembershipPlan, reading: Reading, results: [SceneMembershipResult.StepResult]) async -> Verification {

    var found: Verification = Verification()

    do {

      try await verify(plan, reading: reading, results: results, into: &found)

    } catch {

      found.failure = error

    }

    return found

  }

  private func verify(_ plan: SceneMembershipPlan, reading: Reading, results: [SceneMembershipResult.StepResult], into found: inout Verification) async throws {

    let modem: any LinkingModem = network.modem

    for device in Self.devices(writtenBy: plan) {

      // The device: each slot as read, with the writes made.
      var expected: [UInt16: AllLinkRecord] = Self.slots(of: reading.devices[device] ?? [])
      var removesLastRecord: Bool = false

      for result in results where result.outcome.isDone {

        guard case .device(device) = result.step.endpoint, let address = result.step.record.memoryAddress else {

          continue

        }

        expected[address] = Self.linkStep(result.step, reading: reading).written
        removesLastRecord = removesLastRecord || result.step.risks.contains(.rejectsModemOnceUnlinked)

      }

      do {

        let records: [AllLinkRecordResponse] = try await modem.readAllLinkDatabase(of: device, timeout: Modem.defaultExtendedRequestTimeout)
        let onDevice: [UInt16: AllLinkRecordResponse] = Dictionary(records.map { (response: AllLinkRecordResponse) -> (UInt16, AllLinkRecordResponse) in (response.address, response) }) { (first: AllLinkRecordResponse, _: AllLinkRecordResponse) -> AllLinkRecordResponse in first }
        let end: UInt16 = records.last?.address ?? DeviceDatabaseLayout.firstRecordAddress

        found.deviceChecks[device] = .checked

        for address in Set(expected.keys).union(onDevice.keys).sorted(by: >) {

          let want: AllLinkRecord? = expected[address]
          let got: AllLinkRecordResponse? = onDevice[address]

          if let want, let got, got.record.equalsIgnoringDeviceMaintained(want) {

            continue

          }

          // The device sends no records past its end, so a slot there holding an end marker, or one never
          // expected, reads as nothing; any other record expected there is cut off.
          if got == nil, address < end, want.map({ (record: AllLinkRecord) -> Bool in !record.flags.contains(.usedBefore) }) ?? true {

            continue

          }

          found.mismatches.append(SceneMembershipResult.Mismatch(device: device, mismatch: DatabaseMismatch(
            isDevice: true,
            memoryAddress: address,
            expected: want.map { (record: AllLinkRecord) -> LinkRecord in Self.deviceRecord(record, at: address) },
            found: got.map { (response: AllLinkRecordResponse) -> LinkRecord in LinkRecord(response) }
          )))

        }

      } catch ModemError.deviceRejected(_, .notLinked) where removesLastRecord && plan.devices.first(where: { (known: SceneMembershipDevice) -> Bool in known.address == device })?.engine == .i2cs {

        found.deviceChecks[device] = .rejectsModemAfterUnlinking

      } catch where Self.isDeviceProblem(error) {

        found.deviceChecks[device] = .unanswered

      }

    }

    // The modem: its records in use as read, with the changes made.
    var expectedModem: [AllLinkRecord] = reading.modemRecords.filter { (record: AllLinkRecord) -> Bool in record.flags.contains(.inUse) }

    for result in results where result.outcome.isDone && result.step.endpoint == .modem {

      let written: AllLinkRecord = Self.linkStep(result.step, reading: reading).written

      switch result.step.kind {
      case .addModemRecord:
        expectedModem.append(written)
      default:
        var deleted: AllLinkRecord = written
        deleted.flags.insert(.inUse)

        if let index = expectedModem.firstIndex(where: { (record: AllLinkRecord) -> Bool in Self.isSameModemLink(record, deleted) }) {

          expectedModem.remove(at: index)

        }
      }

    }

    let foundModem: [AllLinkRecord] = try await modem.allLinkRecords().filter { (record: AllLinkRecord) -> Bool in record.flags.contains(.inUse) }
    var unmatched: [AllLinkRecord] = foundModem

    for want in expectedModem {

      if let index = unmatched.firstIndex(where: { (record: AllLinkRecord) -> Bool in Self.isSameModemLink(record, want) }) {

        unmatched.remove(at: index)

      } else {

        found.mismatches.append(SceneMembershipResult.Mismatch(device: nil, mismatch: DatabaseMismatch(isDevice: false, memoryAddress: nil, expected: LinkRecord(want), found: nil)))

      }

    }

    for extra in unmatched {

      found.mismatches.append(SceneMembershipResult.Mismatch(device: nil, mismatch: DatabaseMismatch(isDevice: false, memoryAddress: nil, expected: nil, found: LinkRecord(extra))))

    }

    found.isModemChecked = true

  }

}
