import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Linking and unlinking a device by writing ALL-Link database records directly.
extension DeviceLinkingCoordinator {

  /// The address of the lowest record in a device's database. Insteon's Data Base Format
  /// sheet places device records from `0x0FFF` down to `0x0300`.
  static let lowestRecordAddress: UInt16 = 0x0307

  /// The flags of a record in use that a database link writes: `0xE2` for a controller record
  /// and `0xA2` for a responder record, which also set the product-dependent bit 5.
  static func inUseFlags(isController: Bool) -> AllLinkRecordFlags {

    AllLinkRecordFlags(rawValue: isController ? 0xE2 : 0xA2)

  }

  /// A record that has never been used, which marks the end of a device's database.
  static let endOfDatabase: AllLinkRecord = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  /// The on-level a responder record holds for a byte the catalog names `onLevel` without a
  /// value: full on, the level linking by the device's address records.
  static let fullOnLevel: UInt8 = 0xFF

  /// The ramp rate a responder record holds for a byte the catalog names `rampRate` without a
  /// value: `0x1C`, which the catalog's ramp rate table lists as 0.5 s.
  static let halfSecondRampRate: UInt8 = 0x1C

  // MARK: - Planning

  /// Plans the writes that link a device to the modem by writing both ALL-Link databases
  /// directly, as the Insteon device catalog's links between the device and a Hub say, and
  /// writes nothing.
  ///
  /// The device is asked for its engine and identity, then its database and the modem's are
  /// read from the devices, never from a copy the network holds. For each of the catalog's
  /// links, the plan adds whichever of its two records is missing: the responder's first, then
  /// the controller's, as `Linker` writes them. A record already there stays as it is, data
  /// and all. The device's records go into its first slots not in use, then into the slot of
  /// the record that marks the end of its database, with a new end written into the slot below
  /// first, so the database always has an end. No record in use is overwritten.
  ///
  /// A record the device keeps as a responder holds the data bytes the catalog gives for its
  /// group: a fixed value, the device's own group for a byte that holds it, full on (`0xFF`)
  /// for an on-level, and `0x1C` (0.5 s) for a ramp rate. A controller record holds the
  /// catalog's fixed values and `0x00` otherwise, as do the modem's records.
  ///
  /// - Parameter device: The device.
  /// - Returns: The plan, which ``DeviceLinkingCoordinator/apply(_:)`` carries out.
  /// - Throws: ``DatabaseLinkRefusal`` when the device can't be linked this way, the modem's
  ///   errors, such as `ModemError.deviceTimedOut` when the device doesn't answer, and
  ///   `CancellationError` if the task is canceled.
  public func planDatabaseLink(_ device: InsteonAddress) async throws -> DatabaseLinkPlan {

    try await inTurn(changing: nil) { () async throws -> DatabaseLinkPlan in

      let reading: DatabaseReading = try await readForPlan(device)

      // A description without a profile is the catalog not knowing the identity.
      guard reading.description?.profile != nil else {

        throw reading.identification.identity == nil ? DatabaseLinkRefusal.notIdentified(device) : DatabaseLinkRefusal.notInCatalog(device)

      }

      guard let legs = HubLinkingLeg.legs(of: reading.description, device: device) else {

        throw DatabaseLinkRefusal.noCatalogLinks(device)

      }

      return try Self.linkPlan(reading: reading, legs: legs)

    }

  }

  /// Plans the writes that remove every link between a device and the modem by writing both
  /// ALL-Link databases directly, and writes nothing.
  ///
  /// The device is asked for its engine and identity, then its database and the modem's are
  /// read from the devices. The plan clears the in-use bit of each of the device's records
  /// that names the modem, in its slot, and deletes each of the modem's records that names the
  /// device. With `removingOrphans`, it first also clears each of the device's records that
  /// names a device the modem has no record of; the plan lists them either way. No other
  /// record is written, and no database is compacted.
  ///
  /// The modem's records go first, then the device's, so the device keeps a record of the
  /// modem, which an i2CS device needs to accept a write, until its last one. An i2CS device
  /// rejects the modem once its last record of the modem is removed, so that write can't be
  /// read back.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - removingOrphans: Whether to also remove the device's records that name a device the
  ///     modem doesn't know. Defaults to `false`.
  /// - Returns: The plan, which ``DeviceLinkingCoordinator/apply(_:)`` carries out.
  /// - Throws: ``DatabaseLinkRefusal`` when the device can't be unlinked this way, the modem's
  ///   errors, and `CancellationError` if the task is canceled.
  public func planDatabaseUnlink(_ device: InsteonAddress, removingOrphans: Bool = false) async throws -> DatabaseLinkPlan {

    try await inTurn(changing: nil) { () async throws -> DatabaseLinkPlan in

      let reading: DatabaseReading = try await readForPlan(device)

      return Self.unlinkPlan(reading: reading, removingOrphans: removingOrphans)

    }

  }

  /// What a plan is made from: the device's identification, what the catalog says about it,
  /// and both databases, read fresh.
  struct DatabaseReading {

    var device: InsteonAddress

    var modem: InsteonAddress

    var identification: DeviceIdentification

    var engine: InsteonEngine

    var description: DeviceDescription?

    var deviceRecords: [AllLinkRecordResponse]

    /// Every record in use in the modem's database.
    var allModemRecords: [AllLinkRecord]

    /// What the modem's own records hold, from the catalog's profile of the modem, if any.
    var modemLinkData: ModemLinkData?

    /// The modem's records in use that name the device.
    var modemRecords: [AllLinkRecord] {

      allModemRecords.filter { (record: AllLinkRecord) -> Bool in record.address == device }

    }

  }

  /// Identifies a device, checks that its engine takes database writes, and reads both
  /// databases.
  func readForPlan(_ device: InsteonAddress) async throws -> DatabaseReading {

    let identification: DeviceIdentification = try await network.identify(device)
    var description: DeviceDescription?

    // Only the identity the device reported to this request counts.
    if identification.identity != nil {

      description = await network.registry.device(device)?.deviceDescription

    }

    let engine: InsteonEngine = try Self.checkedEngine(identification, description: description)

    // The copy the network holds may be old, so both databases are read from the devices.
    await network.cache.invalidate(device)

    let records: [AllLinkRecordResponse] = try await network.modem.readAllLinkDatabase(of: device, timeout: Modem.defaultExtendedRequestTimeout)

    try Self.checkReadable(records, of: device, engine: engine)

    let modemInfo: ModemInfo = try await network.modemInfo()
    let modemRecords: [AllLinkRecord] = try await network.modem.allLinkRecords().filter { (record: AllLinkRecord) -> Bool in record.flags.contains(.inUse) }
    let modemProfile: DeviceProfile? = await network.registry.catalog?.profile(
      category: modemInfo.category,
      subcategory: modemInfo.subcategory,
      firmwareVersion: modemInfo.firmwareVersion
    )

    return DatabaseReading(
      device: device,
      modem: modemInfo.address,
      identification: identification,
      engine: engine,
      description: description,
      deviceRecords: records,
      allModemRecords: modemRecords,
      modemLinkData: modemProfile?.modemLinkData
    )

  }

  /// The device's engine, when it takes database writes: i2CS from a modem it accepts, or i2
  /// when the catalog says the device runs i2.
  static func checkedEngine(_ identification: DeviceIdentification, description: DeviceDescription?) throws -> InsteonEngine {

    switch identification.engine {
    case .i2cs:
      guard identification.acceptsModem else {

        throw DatabaseLinkRefusal.rejectsModem(identification.device)

      }

      return .i2cs
    case .i2:
      guard description?.engine == .i2 else {

        throw DatabaseLinkRefusal.unsupportedEngine(identification.device, .i2)

      }

      return .i2
    case .i1, nil:
      throw DatabaseLinkRefusal.unsupportedEngine(identification.device, identification.engine)
    }

  }

  /// Checks that a device's database read whole: ending with its end record, which isn't in
  /// use, and, for an i2CS device, every record's checksum intact.
  static func checkReadable(_ records: [AllLinkRecordResponse], of device: InsteonAddress, engine: InsteonEngine) throws {

    if engine == .i2cs {

      let damaged: Int = records.filter { (record: AllLinkRecordResponse) -> Bool in !record.hasIntactChecksum }.count

      guard damaged == 0 else {

        throw DatabaseLinkRefusal.damagedRecords(device, count: damaged)

      }

    }

    // A last record that's marked in use isn't an end to write over.
    guard let last = records.last, last.isEndOfDatabase, !last.record.flags.contains(.inUse) else {

      throw DatabaseLinkRefusal.noEndOfDatabase(device)

    }

  }

  /// One record a link needs, and who holds it.
  struct NeededRecord: Hashable {

    var isModems: Bool

    var isController: Bool

    var group: AllLinkGroupNumber

    /// The device's group, whose type gives a device's responder record its data.
    var deviceGroup: AllLinkGroupNumber

  }

  /// The plan that adds the records the catalog's legs need and the databases lack.
  static func linkPlan(reading: DatabaseReading, legs: [HubLinkingLeg]) throws -> DatabaseLinkPlan {

    let device: InsteonAddress = reading.device
    let modem: InsteonAddress = reading.modem
    var needed: [NeededRecord] = []

    for leg in legs {

      // The responder's record goes first, as `Linker` writes them.
      switch leg.modemRole {
      case .controller:
        needed.append(NeededRecord(isModems: false, isController: false, group: leg.modemGroup, deviceGroup: leg.deviceGroup))
        needed.append(NeededRecord(isModems: true, isController: true, group: leg.modemGroup, deviceGroup: leg.deviceGroup))
      case .responder:
        needed.append(NeededRecord(isModems: true, isController: false, group: leg.deviceGroup, deviceGroup: leg.deviceGroup))
        needed.append(NeededRecord(isModems: false, isController: true, group: leg.deviceGroup, deviceGroup: leg.deviceGroup))
      }

    }

    let deviceInUse: [AllLinkRecordResponse] = reading.deviceRecords.filter { (response: AllLinkRecordResponse) -> Bool in response.record.flags.contains(.inUse) }
    var seen: Set<NeededRecord> = []
    var missing: [NeededRecord] = []
    var inPlace: [LinkRecord] = []

    for record in needed {

      // Two legs may need the same record; it's written once.
      guard seen.insert(record).inserted else {

        continue

      }

      if record.isModems {

        if let existing = reading.modemRecords.first(where: { (stored: AllLinkRecord) -> Bool in stored.flags.contains(.controller) == record.isController && stored.group == record.group }) {

          inPlace.append(LinkRecord(existing))

        } else {

          missing.append(record)

        }

      } else if let existing = deviceInUse.first(where: { (stored: AllLinkRecordResponse) -> Bool in

        stored.record.address == modem && stored.record.flags.contains(.controller) == record.isController && stored.record.group == record.group

      }) {

        inPlace.append(LinkRecord(existing))

      } else {

        missing.append(record)

      }

    }

    // Room for the device's records: its slots not in use, then one more for each slot the
    // end can move down.
    let deviceAdds: Int = missing.filter { (record: NeededRecord) -> Bool in !record.isModems }.count
    var free: [UInt16] = reading.deviceRecords.filter { (response: AllLinkRecordResponse) -> Bool in

      !response.isEndOfDatabase && !response.record.flags.contains(.inUse)

    }.map(\.address)
    var end: UInt16 = reading.deviceRecords.last?.address ?? 0x0FFF
    let roomBelowEnd: Int = end >= lowestRecordAddress + 8 ? Int((end - lowestRecordAddress) / 8) : 0

    guard deviceAdds <= free.count + roomBelowEnd else {

      throw DatabaseLinkRefusal.databaseFull(device, needed: deviceAdds, available: free.count + roomBelowEnd)

    }

    var steps: [DatabaseLinkStep] = []

    for record in missing {

      if record.isModems {

        let data: [UInt8] = modemData(reading.modemLinkData, isController: record.isController, identity: reading.identification.identity)
        let written = AllLinkRecord(
          flags: inUseFlags(isController: record.isController),
          group: record.group,
          address: device,
          data1: data[0],
          data2: data[1],
          data3: data[2]
        )

        steps.append(DatabaseLinkStep(kind: .addModemRecord, written: written, memoryAddress: nil))

        continue

      }

      let data: [UInt8] = record.isController
        ? controllerData(reading.description, group: record.deviceGroup)
        : try responderData(reading.description, device: device, deviceGroup: record.deviceGroup)
      let written = AllLinkRecord(
        flags: inUseFlags(isController: record.isController),
        group: record.group,
        address: modem,
        data1: data[0],
        data2: data[1],
        data3: data[2]
      )

      if !free.isEmpty {

        steps.append(DatabaseLinkStep(kind: .addDeviceRecord, written: written, memoryAddress: free.removeFirst()))

      } else {

        // The slot below the end becomes the new end before the end's slot is written, so the
        // database always has an end, even if the second write fails.
        steps.append(DatabaseLinkStep(kind: .markEndOfDatabase, written: endOfDatabase, memoryAddress: end - 8))
        steps.append(DatabaseLinkStep(kind: .addDeviceRecord, written: written, memoryAddress: end))
        end -= 8

      }

    }

    return DatabaseLinkPlan(
      device: device,
      modem: modem,
      direction: .link,
      info: reading.description.map { (description: DeviceDescription) -> DeviceInfo in DeviceInfo(description) },
      engine: reading.engine,
      steps: steps,
      linksInPlace: inPlace,
      orphans: [],
      deviceRecords: reading.deviceRecords,
      modemRecords: reading.modemRecords,
      allModemRecords: reading.allModemRecords
    )

  }

  /// The data bytes of a record the modem keeps for the device, from the catalog's profile of
  /// the modem: a fixed value, or a byte of the identity the device reported. A byte the
  /// catalog doesn't give, or one of an identity the device didn't report, is `0x00`.
  static func modemData(_ linkData: ModemLinkData?, isController: Bool, identity: SetButtonPressed?) -> [UInt8] {

    var data: [UInt8] = [0x00, 0x00, 0x00]
    let bytes: [ModemLinkDataByte] = (isController ? linkData?.controller : linkData?.responder) ?? []

    for byte in bytes where (1...3).contains(byte.position) {

      if let value = byte.value {

        data[byte.position - 1] = value

      } else if let identity, byte.identity == .category {

        data[byte.position - 1] = identity.category.rawValue

      } else if let identity, byte.identity == .subcategory {

        data[byte.position - 1] = identity.subcategory.rawValue

      } else if let identity, byte.identity == .firmware, let firmware = identity.firmwareVersion {

        data[byte.position - 1] = firmware.rawValue

      }

    }

    return data

  }

  /// The plan that removes every record of a link between the device and the modem, and the
  /// orphans when asked.
  static func unlinkPlan(reading: DatabaseReading, removingOrphans: Bool) -> DatabaseLinkPlan {

    let device: InsteonAddress = reading.device
    let modem: InsteonAddress = reading.modem
    let known: Set<InsteonAddress> = Set(reading.allModemRecords.map(\.address)).union([modem])
    var orphans: [DatabaseLinkStep] = []
    var modemLinks: [DatabaseLinkStep] = []
    var deviceLinks: [DatabaseLinkStep] = []

    for response in reading.deviceRecords where response.record.flags.contains(.inUse) {

      var cleared: AllLinkRecord = response.record
      cleared.flags.remove(.inUse)

      if response.record.address == modem {

        deviceLinks.append(DatabaseLinkStep(kind: .removeDeviceRecord, written: cleared, memoryAddress: response.address))

      } else if !known.contains(response.record.address) {

        orphans.append(DatabaseLinkStep(kind: .removeOrphanRecord, written: cleared, memoryAddress: response.address))

      }

    }

    for record in reading.modemRecords {

      var deleted: AllLinkRecord = record
      deleted.flags.remove(.inUse)

      modemLinks.append(DatabaseLinkStep(kind: .removeModemRecord, written: deleted, memoryAddress: nil))

    }

    // The device keeps a record of the modem until its last one, so an i2CS device accepts
    // each write before it.
    let steps: [DatabaseLinkStep] = (removingOrphans ? orphans : []) + modemLinks + deviceLinks

    return DatabaseLinkPlan(
      device: device,
      modem: modem,
      direction: .unlink,
      info: reading.description.map { (description: DeviceDescription) -> DeviceInfo in DeviceInfo(description) },
      engine: reading.engine,
      steps: steps,
      linksInPlace: [],
      orphans: orphans.map(\.record).map { (record: LinkRecord) -> LinkRecord in

        // The orphan as it is, in use.
        var inUse: LinkRecord = record
        inUse.isInUse = true

        return inUse

      },
      deviceRecords: reading.deviceRecords,
      modemRecords: reading.modemRecords,
      allModemRecords: reading.allModemRecords
    )

  }

  /// The data bytes of a responder record the device keeps for a link in which `deviceGroup`
  /// is its group.
  static func responderData(_ description: DeviceDescription?, device: InsteonAddress, deviceGroup: AllLinkGroupNumber) throws -> [UInt8] {

    guard
      let description,
      let type = description.groupType(forGroup: deviceGroup) ?? description.mainGroupType,
      !type.linkData.responder.isEmpty
    else {

      throw DatabaseLinkRefusal.undescribedLinkData(device, group: deviceGroup)

    }

    var data: [UInt8] = [0x00, 0x00, 0x00]

    for byte in type.linkData.responder where (1...3).contains(byte.position) {

      if let value = byte.value {

        data[byte.position - 1] = value

      } else if byte.isPerGroup {

        data[byte.position - 1] = deviceGroup.rawValue

      } else if byte.name.rawValue == "onLevel" {

        data[byte.position - 1] = fullOnLevel

      } else if byte.name.rawValue == "rampRate" {

        data[byte.position - 1] = halfSecondRampRate

      } else {

        throw DatabaseLinkRefusal.unknownLinkDataByte(device, name: byte.name.rawValue)

      }

    }

    return data

  }

  /// The data bytes of a controller record the device keeps for one of its groups: the
  /// catalog's fixed values, the group for a byte that holds it, and `0x00` otherwise.
  static func controllerData(_ description: DeviceDescription?, group: AllLinkGroupNumber) -> [UInt8] {

    var data: [UInt8] = [0x00, 0x00, 0x00]

    guard let type = description?.groupType(forGroup: group) ?? description?.mainGroupType else {

      return data

    }

    for byte in type.linkData.controller where (1...3).contains(byte.position) {

      if let value = byte.value {

        data[byte.position - 1] = value

      } else if byte.isPerGroup {

        data[byte.position - 1] = group.rawValue

      }

    }

    return data

  }

  // MARK: - Applying

  /// Carries out a plan from ``DeviceLinkingCoordinator/planDatabaseLink(_:)`` or
  /// ``DeviceLinkingCoordinator/planDatabaseUnlink(_:removingOrphans:)``.
  ///
  /// Both databases are read again first; when either changed since the plan was made,
  /// nothing is written. Each step is then made in order and read back. Before a device's
  /// record is written, its slot is read again, and the steps stop if it changed. A device's
  /// record is written with Read/Write ALL-Link Database (`0x2F`) and read back from its slot;
  /// a modem's record is added or deleted with Manage ALL-Link Record (`0x6F`) and the modem's
  /// records for the device in the group are read back. A step that reads back differently is
  /// made once more, and only then; when it still reads back differently, or the device or
  /// modem doesn't answer or rejects it, the steps after it aren't made. Last, both databases
  /// are read again and compared with what the steps that were made should have left; every
  /// other record is expected unchanged.
  ///
  /// Nothing else is sent: no operating flag is read or written, and no device is put into
  /// linking mode. Afterward, the network forgets its copies of the device's and the modem's
  /// databases, so they're read again when next needed.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: Each step's outcome and what reading both databases again found.
  /// - Throws: ``DatabaseLinkRefusal`` when a database changed or doesn't read whole, before
  ///   anything is written. ``DatabaseLinkInterrupted`` when the steps stop partway for
  ///   anything but the device's own timeouts and rejections, such as the modem's error, a
  ///   slot that changed before it was written, or `CancellationError`: it carries the
  ///   outcome of each step, and what reading the databases again found when they could be
  ///   read. The device's own timeouts and rejections don't throw; a step's outcome says so.
  public func apply(_ plan: DatabaseLinkPlan) async throws -> DatabaseLinkResult {

    try await inTurn(changing: plan.device) { () async throws -> DatabaseLinkResult in

      let device: InsteonAddress = plan.device
      let modem: any LinkingModem = network.modem

      // Nothing is written unless both databases are as the plan read them.
      let records: [AllLinkRecordResponse] = try await modem.readAllLinkDatabase(of: device, timeout: Modem.defaultExtendedRequestTimeout)

      try Self.checkReadable(records, of: device, engine: plan.engine)

      let modemAddress: InsteonAddress = try await network.modemInfo().address
      let modemRecords: [AllLinkRecord] = try await modem.allLinkRecords().filter { (record: AllLinkRecord) -> Bool in record.flags.contains(.inUse) }

      guard
        modemAddress == plan.modem,
        Self.isSame(records, plan.deviceRecords),
        Self.isSameModemRecords(modemRecords, plan.allModemRecords)
      else {

        throw DatabaseLinkRefusal.changedSincePlanned(device)

      }

      var results: [DatabaseLinkResult.StepResult] = []
      var isStopped: Bool = false
      var interruption: (any Error)?
      // What each slot of the device's database holds, as read and as written since.
      var slots: [UInt16: AllLinkRecord] = Self.slots(of: plan.deviceRecords)
      let lastDeviceLinkIndex: Int? = plan.steps.lastIndex { (step: DatabaseLinkStep) -> Bool in step.kind == .removeDeviceRecord }

      for (index, step) in plan.steps.enumerated() {

        guard !isStopped else {

          results.append(DatabaseLinkResult.StepResult(step: step, outcome: .notReached))

          continue

        }

        do {

          let outcome: DatabaseLinkStepOutcome

          if step.isDeviceStep, let address = step.record.memoryAddress {

            if let expected = slots[address] {

              let holds: Bool

              do {

                holds = try await slotHolds(expected, at: address, of: device, engine: plan.engine)

              } catch where Self.isDeviceProblem(error) {

                results.append(DatabaseLinkResult.StepResult(step: step, outcome: .unanswered))
                isStopped = true

                continue

              }

              guard holds else {

                // Something else wrote the slot since it was read, so it isn't written over.
                results.append(DatabaseLinkResult.StepResult(step: step, outcome: .notReached))
                interruption = DatabaseLinkRefusal.changedSincePlanned(device)
                isStopped = true

                continue

              }

            }

            // An i2CS device rejects the modem once its last record of the modem is gone.
            let mayBecomeUnreadable: Bool = plan.engine == .i2cs && index == lastDeviceLinkIndex

            outcome = try await writeDeviceRecord(step, of: device, engine: plan.engine, mayBecomeUnreadable: mayBecomeUnreadable)

            if outcome.isDone {

              slots[address] = step.written

            }

          } else {

            outcome = try await writeModemRecord(step, of: device)

          }

          results.append(DatabaseLinkResult.StepResult(step: step, outcome: outcome))
          isStopped = !outcome.isDone

        } catch {

          // It isn't known whether the step took; the steps after it aren't made.
          results.append(DatabaseLinkResult.StepResult(step: step, outcome: .unanswered))
          interruption = error
          isStopped = true

        }

      }

      var mismatches: [DatabaseMismatch] = []
      var deviceCheck: DatabaseLinkResult.DeviceCheck = .unanswered

      // A canceled task reads nothing more, so the databases aren't read again.
      if !(interruption is CancellationError) {

        do {

          (mismatches, deviceCheck) = try await verify(plan, results: results)

        } catch {

          interruption = interruption ?? error

        }

      }

      let result = DatabaseLinkResult(plan: plan, steps: results, mismatches: mismatches, deviceCheck: deviceCheck)

      if let interruption {

        throw DatabaseLinkInterrupted(result: result, cause: interruption)

      }

      await network.recordLinkChange(of: device, answered: true)

      return result

    }

  }

  /// Each slot of a device's database and the record it holds.
  static func slots(of records: [AllLinkRecordResponse]) -> [UInt16: AllLinkRecord] {

    var slots: [UInt16: AllLinkRecord] = [:]

    for response in records {

      slots[response.address] = response.record

    }

    return slots

  }

  /// Whether a slot of a device's database holds a record, read again just before it's
  /// written.
  ///
  /// - Throws: The device's timeout or rejection, and the modem's errors.
  func slotHolds(_ expected: AllLinkRecord, at address: UInt16, of device: InsteonAddress, engine: InsteonEngine) async throws -> Bool {

    let current: AllLinkRecordResponse = try await readRecord(at: address, of: device, engine: engine)

    return Self.isSame(current.record, expected)

  }

  /// Whether a device's records read as a plan's did, but for the flags a device may change
  /// on its own.
  static func isSame(_ records: [AllLinkRecordResponse], _ planned: [AllLinkRecordResponse]) -> Bool {

    records.count == planned.count && zip(records, planned).allSatisfy { (pair: (AllLinkRecordResponse, AllLinkRecordResponse)) -> Bool in

      pair.0.address == pair.1.address && isSame(pair.0.record, pair.1.record)

    }

  }

  /// Whether the modem's records are those a plan read, in any order.
  static func isSameModemRecords(_ records: [AllLinkRecord], _ planned: [AllLinkRecord]) -> Bool {

    records.count == planned.count && records.allSatisfy { (record: AllLinkRecord) -> Bool in

      records.filter { (other: AllLinkRecord) -> Bool in other == record }.count == planned.filter { (other: AllLinkRecord) -> Bool in other == record }.count

    }

  }

  /// Whether two records are the same but for the flags a device may change on its own, such
  /// as its smart hop count.
  static func isSame(_ record: AllLinkRecord, _ other: AllLinkRecord) -> Bool {

    var record: AllLinkRecord = record, other: AllLinkRecord = other
    record.flags.subtract(.deviceMaintained)
    other.flags.subtract(.deviceMaintained)

    return record == other

  }

  /// Whether an error is the device's own: a timeout or a rejection, rather than the modem's
  /// or the connection's.
  static func isDeviceProblem(_ error: any Error) -> Bool {

    guard let error = error as? ModemError else {

      return false

    }

    switch error {
    case .deviceTimedOut, .deviceRejected:
      return true
    default:
      return false
    }

  }

  /// Writes a device's record into its slot and reads it back, writing it once more when it
  /// reads back differently.
  func writeDeviceRecord(_ step: DatabaseLinkStep, of device: InsteonAddress, engine: InsteonEngine, mayBecomeUnreadable: Bool) async throws -> DatabaseLinkStepOutcome {

    guard let address = step.record.memoryAddress else {

      preconditionFailure("A device's step has a memory address.")

    }

    let modem: any LinkingModem = network.modem
    let message: ExtendedMessage = AllLinkDatabaseRequest.write(step.written, address: address).message(to: device)
    var rejections: Int = 0

    for attempt in 1...2 {

      var isAcknowledged: Bool = false

      do {

        _ = try await modem.request(message, timeout: Modem.defaultExtendedRequestTimeout)
        isAcknowledged = true

      } catch ModemError.deviceRejected {

        rejections += 1

      } catch ModemError.deviceTimedOut {

        // Whether it took is read back below.

      }

      let readBack: AllLinkRecordResponse

      do {

        readBack = try await readRecord(at: address, of: device, engine: engine)

      } catch ModemError.deviceRejected(_, .notLinked) where mayBecomeUnreadable && isAcknowledged {

        // The device acknowledged removing its last record of the modem, and rejects the modem
        // from then on.
        return .unverifiable

      } catch where Self.isDeviceProblem(error) {

        return rejections > 0 ? .rejected : .unanswered

      }

      if Self.isSame(readBack.record, step.written) {

        return attempt == 1 ? .written : .writtenOnRetry

      }

    }

    return rejections == 2 ? .rejected : .notWritten

  }

  /// Reads one record of a device's database, reading it once more when an i2CS device's
  /// checksum fails.
  func readRecord(at address: UInt16, of device: InsteonAddress, engine: InsteonEngine) async throws -> AllLinkRecordResponse {

    let modem: any LinkingModem = network.modem
    let first: AllLinkRecordResponse = try await modem.readAllLinkRecord(of: device, at: address, timeout: Modem.defaultExtendedRequestTimeout)

    guard engine == .i2cs, !first.hasIntactChecksum else {

      return first

    }

    let second: AllLinkRecordResponse = try await modem.readAllLinkRecord(of: device, at: address, timeout: Modem.defaultExtendedRequestTimeout)

    guard second.hasIntactChecksum else {

      throw ModemError.deviceTimedOut(device)

    }

    return second

  }

  /// Adds or deletes a modem's record and reads the modem's records for the device in the
  /// group back, making the change once more when it didn't take.
  func writeModemRecord(_ step: DatabaseLinkStep, of device: InsteonAddress) async throws -> DatabaseLinkStepOutcome {

    let modem: any LinkingModem = network.modem
    let record: AllLinkRecord = step.written
    let isController: Bool = record.flags.contains(.controller)
    let before: [AllLinkRecord] = try await modem.allLinkRecords(group: record.group, device: device)
    var rejections: Int = 0

    for attempt in 1...2 {

      let command: SerialCommand

      switch step.kind {
      case .addModemRecord:
        command = .manageAllLinkRecord(action: isController ? .modifyFirstControllerOrAdd : .modifyFirstResponderOrAdd, record: record)
      default:
        // The modem deletes the first record of the group that names the device, whatever its
        // role; the plan deletes each of them.
        command = .manageAllLinkRecord(action: .deleteFirst, record: AllLinkRecord(flags: [], group: record.group, address: device))
      }

      do {

        try await modem.send(command)

      } catch ModemError.rejected(.manageAllLinkRecord) {

        // A modem whose database is full rejects an add; whether anything changed is read
        // back below.
        rejections += 1

      }

      let after: [AllLinkRecord] = try await modem.allLinkRecords(group: record.group, device: device)
      let isDone: Bool

      if step.kind == .addModemRecord {

        isDone = after.contains { (stored: AllLinkRecord) -> Bool in

          stored.flags.contains(.inUse) && stored.flags.contains(.controller) == isController

        }

      } else {

        isDone = after.count < before.count

      }

      if isDone {

        return attempt == 1 ? .written : .writtenOnRetry

      }

    }

    return rejections == 2 ? .rejected : .notWritten

  }

  /// Reads both databases again and compares them with what the steps that were made should
  /// have left.
  func verify(_ plan: DatabaseLinkPlan, results: [DatabaseLinkResult.StepResult]) async throws -> ([DatabaseMismatch], DatabaseLinkResult.DeviceCheck) {

    let device: InsteonAddress = plan.device
    let modem: any LinkingModem = network.modem
    var mismatches: [DatabaseMismatch] = []
    var deviceCheck: DatabaseLinkResult.DeviceCheck = .checked

    // The device: each slot as read, with the writes made.
    var expected: [UInt16: AllLinkRecord] = Self.slots(of: plan.deviceRecords)

    for result in results where result.step.isDeviceStep && result.outcome.isDone {

      if let address = result.step.record.memoryAddress {

        expected[address] = result.step.written

      }

    }

    do {

      let records: [AllLinkRecordResponse] = try await modem.readAllLinkDatabase(of: device, timeout: Modem.defaultExtendedRequestTimeout)
      let found: [UInt16: AllLinkRecordResponse] = Dictionary(records.map { (response: AllLinkRecordResponse) -> (UInt16, AllLinkRecordResponse) in (response.address, response) }) { (first: AllLinkRecordResponse, _: AllLinkRecordResponse) -> AllLinkRecordResponse in first }
      let end: UInt16 = records.last?.address ?? 0x0FFF

      for address in Set(expected.keys).union(found.keys).sorted(by: >) {

        let want: AllLinkRecord? = expected[address]
        let got: AllLinkRecordResponse? = found[address]

        if let want, let got, Self.isSame(got.record, want) {

          continue

        }

        // The device sends no records past its end, so a slot there holding an end marker, or
        // one never expected, reads as nothing; any other record expected there is cut off.
        if got == nil, address < end, want.map({ (record: AllLinkRecord) -> Bool in !record.flags.contains(.usedBefore) }) ?? true {

          continue

        }

        mismatches.append(DatabaseMismatch(
          isDevice: true,
          memoryAddress: address,
          expected: want.map { (record: AllLinkRecord) -> LinkRecord in Self.deviceRecord(record, at: address) },
          found: got.map { (response: AllLinkRecordResponse) -> LinkRecord in LinkRecord(response) }
        ))

      }

    } catch ModemError.deviceRejected(_, .notLinked) where plan.engine == .i2cs && plan.direction == .unlink {

      deviceCheck = .rejectsModemAfterUnlinking

    } catch where Self.isDeviceProblem(error) {

      deviceCheck = .unanswered

    }

    // The modem: its records for the device as read, with the changes made.
    var expectedModem: [AllLinkRecord] = plan.modemRecords

    for result in results where !result.step.isDeviceStep && result.outcome.isDone {

      switch result.step.kind {
      case .addModemRecord:
        expectedModem.append(result.step.written)
      default:
        var deleted: AllLinkRecord = result.step.written
        deleted.flags.insert(.inUse)

        if let index = expectedModem.firstIndex(where: { (record: AllLinkRecord) -> Bool in Self.isSameModemLink(record, deleted) }) {

          expectedModem.remove(at: index)

        }
      }

    }

    let foundModem: [AllLinkRecord] = try await modem.allLinkRecords().filter { (record: AllLinkRecord) -> Bool in

      record.flags.contains(.inUse) && record.address == device

    }

    var unmatched: [AllLinkRecord] = foundModem

    for want in expectedModem {

      if let index = unmatched.firstIndex(where: { (record: AllLinkRecord) -> Bool in Self.isSameModemLink(record, want) }) {

        unmatched.remove(at: index)

      } else {

        mismatches.append(DatabaseMismatch(isDevice: false, memoryAddress: nil, expected: LinkRecord(want), found: nil))

      }

    }

    for extra in unmatched {

      mismatches.append(DatabaseMismatch(isDevice: false, memoryAddress: nil, expected: nil, found: LinkRecord(extra)))

    }

    return (mismatches, deviceCheck)

  }

  /// Whether two of the modem's records are of the same link: the same role and group.
  static func isSameModemLink(_ record: AllLinkRecord, _ other: AllLinkRecord) -> Bool {

    record.flags.contains(.controller) == other.flags.contains(.controller) && record.group == other.group && record.address == other.address

  }

  /// A device's record at a memory address.
  static func deviceRecord(_ record: AllLinkRecord, at address: UInt16) -> LinkRecord {

    var linkRecord: LinkRecord = LinkRecord(record)
    linkRecord.memoryAddress = address
    linkRecord.isEndOfDatabase = !record.flags.contains(.usedBefore)

    return linkRecord

  }

}
