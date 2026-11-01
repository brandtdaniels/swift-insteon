import Foundation
import InsteonProtocol

/// Whether a ``DatabaseLinkPlan`` links a device to the modem or unlinks it.
public enum DatabaseLinkDirection: String, Hashable, Sendable {

  /// Writes the records of the links the Insteon device catalog gives the device.
  case link

  /// Removes the records of every link between the device and the modem.
  case unlink

}

/// One write of a ``DatabaseLinkPlan``: a record written into a slot of the device's ALL-Link
/// database, or a record the modem adds or deletes with Manage ALL-Link Record.
public struct DatabaseLinkStep: Hashable, Sendable {

  /// What a step writes.
  public enum Kind: String, Hashable, Sendable {

    /// Writes a record of a link into a slot of the device's database that isn't in use, or
    /// into the slot of the record that marks the database's end.
    case addDeviceRecord

    /// Writes a record that marks the end of the device's database into the slot below the
    /// one the next step fills, so the database keeps an end.
    case markEndOfDatabase

    /// Clears the in-use bit of the device's record of a link with the modem.
    case removeDeviceRecord

    /// Clears the in-use bit of a record of the device's that names a device the modem
    /// doesn't know.
    case removeOrphanRecord

    /// Adds a record to the modem's database.
    case addModemRecord

    /// Deletes one of the modem's records for the device in a group.
    case removeModemRecord

  }

  /// What the step writes.
  public internal(set) var kind: Kind

  /// The record as the step leaves it: in the device's database at its
  /// ``LinkRecord/memoryAddress``, or in the modem's.
  public internal(set) var record: LinkRecord

  /// The record's bytes as written: the device's record at its memory address, or the record
  /// the modem is sent.
  var written: AllLinkRecord

  /// Whether the step writes to the device rather than the modem.
  public var isDeviceStep: Bool {

    switch kind {
    case .addDeviceRecord, .markEndOfDatabase, .removeDeviceRecord, .removeOrphanRecord:
      true
    case .addModemRecord, .removeModemRecord:
      false
    }

  }

  /// Creates a step.
  ///
  /// - Parameters:
  ///   - kind: What the step writes.
  ///   - written: The record's bytes as written.
  ///   - memoryAddress: Where the record goes in the device's database, or `nil` for the modem's.
  init(kind: Kind, written: AllLinkRecord, memoryAddress: UInt16?) {

    self.kind = kind
    self.written = written

    var record: LinkRecord = LinkRecord(written)
    record.memoryAddress = memoryAddress
    record.isEndOfDatabase = memoryAddress != nil && !written.flags.contains(.usedBefore)
    self.record = record

  }

}

/// The writes that link a device to the modem, or unlink it, by writing ALL-Link database
/// records directly, from a fresh reading of both databases.
///
/// Only the coordinator makes a plan, and its writes can't be changed, so a plan carried out
/// writes only what was read and shown.
///
/// ``DeviceLinkingCoordinator/planDatabaseLink(_:)`` and
/// ``DeviceLinkingCoordinator/planDatabaseUnlink(_:removingOrphans:)`` make a plan and write
/// nothing. ``DeviceLinkingCoordinator/apply(_:)`` carries it out, after checking that neither
/// database changed since it was read.
public struct DatabaseLinkPlan: Hashable, Sendable {

  /// The device.
  public internal(set) var device: InsteonAddress

  /// The modem's address, which the device's records of their links name.
  public internal(set) var modem: InsteonAddress

  /// Whether the plan links or unlinks.
  public internal(set) var direction: DatabaseLinkDirection

  /// What the Insteon device catalog says about the device, if it describes it.
  public internal(set) var info: DeviceInfo?

  /// The device's engine, as it reported it.
  public internal(set) var engine: InsteonEngine

  /// The writes, in the order they're made.
  public internal(set) var steps: [DatabaseLinkStep]

  /// The records of the links already in place, in the device's database and the modem's,
  /// which the plan leaves as they are.
  public internal(set) var linksInPlace: [LinkRecord]

  /// The records of the device's that name a device the modem doesn't know, each at its
  /// memory address. An unlink plan removes them only when asked to.
  public internal(set) var orphans: [LinkRecord]

  /// The device's records as they were read, from its first record to the one that marks the
  /// end of its database.
  var deviceRecords: [AllLinkRecordResponse]

  /// The modem's records in use that name the device, as they were read.
  var modemRecords: [AllLinkRecord]

  /// Whether the plan writes nothing.
  public var isEmpty: Bool {

    steps.isEmpty

  }

  /// Whether the plan removes the device's records that name a device the modem doesn't
  /// know, rather than only listing them.
  public var removesOrphans: Bool {

    steps.contains { (step: DatabaseLinkStep) -> Bool in step.kind == .removeOrphanRecord }

  }

  /// Whether the device rejects the modem once the plan removes its last record of the modem,
  /// as an i2CS device does, so that write can't be read back.
  public var rejectsModemOnceUnlinked: Bool {

    direction == .unlink && engine == .i2cs && steps.contains { (step: DatabaseLinkStep) -> Bool in step.kind == .removeDeviceRecord }

  }

  /// The steps that write to the device.
  public var deviceSteps: [DatabaseLinkStep] {

    steps.filter(\.isDeviceStep)

  }

  /// The steps that write to the modem.
  public var modemSteps: [DatabaseLinkStep] {

    steps.filter { (step: DatabaseLinkStep) -> Bool in !step.isDeviceStep }

  }

}

/// Why a device can't be linked or unlinked by writing its ALL-Link database. Nothing is
/// written when one is thrown.
public enum DatabaseLinkRefusal: Error, Hashable, Sendable {

  /// The device didn't report its identity to ID Request, so the Insteon device catalog can't
  /// say how to link it or whether its engine takes database writes.
  case notIdentified(InsteonAddress)

  /// The device's engine doesn't take database writes, or the catalog doesn't confirm that it
  /// does: an i1 device, an engine the package doesn't know, or an i2 device the catalog
  /// doesn't say runs i2.
  case unsupportedEngine(InsteonAddress, InsteonEngine?)

  /// The device runs i2CS and rejects the modem, as it does until it's linked to the modem in
  /// some way, so it rejects database writes too.
  case rejectsModem(InsteonAddress)

  /// The Insteon device catalog doesn't describe the identity the device reported.
  case notInCatalog(InsteonAddress)

  /// The catalog gives no links between the device and a Hub, so which records to write isn't
  /// known.
  case noCatalogLinks(InsteonAddress)

  /// The catalog doesn't say what the data bytes of the device's responder record hold for
  /// one of its groups.
  case undescribedLinkData(InsteonAddress, group: AllLinkGroupNumber)

  /// The catalog names a data byte of the device's responder record without a value to write.
  case unknownLinkDataByte(InsteonAddress, name: String)

  /// Records of the device's database failed their checksum, so what they hold can't be
  /// trusted.
  case damagedRecords(InsteonAddress, count: Int)

  /// The device's database ended without the record that marks its end.
  case noEndOfDatabase(InsteonAddress)

  /// The device's database has room for fewer records than the plan adds.
  case databaseFull(InsteonAddress, needed: Int, available: Int)

  /// The device's database or the modem's records for it changed since the plan was made.
  case changedSincePlanned(InsteonAddress)

}

extension DatabaseLinkRefusal: CustomStringConvertible, LocalizedError {

  /// A one-line explanation of the refusal.
  public var description: String {

    switch self {
    case let .notIdentified(device):
      "\(device) didn't report its identity, so the Insteon device catalog can't say how to write its ALL-Link database. Nothing was written."
    case let .unsupportedEngine(device, engine):
      "\(device) \(Self.engineText(engine)), so its ALL-Link database isn't written directly. Nothing was written."
    case let .rejectsModem(device):
      "\(device) runs i2CS and rejects the modem, as it does until it's linked to it, so it rejects database writes too. Link it with linking mode or its SET button first. Nothing was written."
    case let .notInCatalog(device):
      "The Insteon device catalog doesn't describe the identity \(device) reported, so which records to write isn't known. Nothing was written."
    case let .noCatalogLinks(device):
      "The Insteon device catalog gives no links between \(device) and a Hub, so which records to write isn't known. Nothing was written."
    case let .undescribedLinkData(device, group):
      "The Insteon device catalog doesn't say what the data bytes of \(device)'s responder record hold for its group \(group.rawValue). Nothing was written."
    case let .unknownLinkDataByte(device, name):
      "The Insteon device catalog gives no value to write for the data byte \(name) of \(device)'s responder record. Nothing was written."
    case let .damagedRecords(device, count):
      "\(count) of \(device)'s ALL-Link records failed their checksum, so what they hold can't be trusted. Nothing was written; try again."
    case let .noEndOfDatabase(device):
      "\(device)'s ALL-Link database ended without the record that marks its end. Nothing was written; try again."
    case let .databaseFull(device, needed, available):
      "\(device)'s ALL-Link database has room for \(available) more \(available == 1 ? "record" : "records"), and \(needed) are needed. Nothing was written."
    case let .changedSincePlanned(device):
      "\(device)'s ALL-Link database or the modem's records for it changed since the plan was made. Nothing was written; plan again."
    }

  }

  /// The same text as the refusal's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

  private static func engineText(_ engine: InsteonEngine?) -> String {

    switch engine {
    case .i1:
      "runs i1, which has no database writes"
    case .i2:
      "reports i2, and the Insteon device catalog doesn't confirm it runs i2"
    case .i2cs, nil:
      "reports an engine this package doesn't know"
    }

  }

}

/// What became of one step of a ``DatabaseLinkPlan``.
public enum DatabaseLinkStepOutcome: String, Hashable, Sendable {

  /// The record read back as written.
  case written

  /// The record read back differently once and was written again, then read back as written.
  case writtenOnRetry

  /// The record read back differently after it was written twice. The steps after it weren't
  /// made.
  case notWritten

  /// The device or the modem didn't answer, or rejected the write or the read back, so it
  /// isn't known whether the record was written. The steps after it weren't made.
  case unanswered

  /// The step removed the device's last record of the modem, and the device, which runs
  /// i2CS, rejects the modem from then on, so the record can't be read back.
  case unverifiable

  /// An earlier step failed, so the step wasn't made.
  case notReached

  /// Whether the step did what it was meant to, or can't be checked only because it did.
  public var isDone: Bool {

    switch self {
    case .written, .writtenOnRetry, .unverifiable:
      true
    case .notWritten, .unanswered, .notReached:
      false
    }

  }

}

/// A record that isn't as a ``DatabaseLinkResult`` expects it after the steps that were made:
/// in the device's database at a memory address, or in the modem's.
public struct DatabaseMismatch: Hashable, Sendable {

  /// Whether the record is the device's rather than the modem's.
  public var isDevice: Bool

  /// Where the record is in the device's database, or `nil` for one of the modem's.
  public var memoryAddress: UInt16?

  /// The record expected, or `nil` when none was.
  public var expected: LinkRecord?

  /// The record found, or `nil` when none was.
  public var found: LinkRecord?

  /// Creates a mismatch.
  ///
  /// - Parameters:
  ///   - isDevice: Whether the record is the device's.
  ///   - memoryAddress: Where it is in the device's database, or `nil` for the modem's.
  ///   - expected: The record expected, or `nil`.
  ///   - found: The record found, or `nil`.
  public init(isDevice: Bool, memoryAddress: UInt16?, expected: LinkRecord?, found: LinkRecord?) {

    self.isDevice = isDevice
    self.memoryAddress = memoryAddress
    self.expected = expected
    self.found = found

  }

}

/// What ``DeviceLinkingCoordinator/apply(_:)`` did: each step's outcome, and what reading
/// both databases again afterward found.
public struct DatabaseLinkResult: Hashable, Sendable {

  /// One step and its outcome.
  public struct StepResult: Hashable, Sendable {

    /// The step.
    public var step: DatabaseLinkStep

    /// What became of it.
    public var outcome: DatabaseLinkStepOutcome

    /// Creates a step's result.
    public init(step: DatabaseLinkStep, outcome: DatabaseLinkStepOutcome) {

      self.step = step
      self.outcome = outcome

    }

  }

  /// The plan carried out.
  public var plan: DatabaseLinkPlan

  /// Each step, in order, with its outcome.
  public var steps: [StepResult]

  /// The records not as expected after the steps that were made, from reading both databases
  /// again.
  public var mismatches: [DatabaseMismatch]

  /// What reading the device's database again afterward found.
  public enum DeviceCheck: String, Hashable, Sendable {

    /// The database was read and compared.
    case checked

    /// The device runs i2CS and rejects the modem once its last record of the modem is
    /// removed, as unlinking does, so its database can't be read again.
    case rejectsModemAfterUnlinking

    /// The device didn't answer, or rejected the modem, so its database wasn't compared.
    case unanswered

  }

  /// What reading the device's database again afterward found.
  public var deviceCheck: DeviceCheck

  /// Whether every step was made and both databases read back as expected, or, after
  /// unlinking an i2CS device, the modem's did and the device rejects the modem.
  public var isComplete: Bool {

    steps.allSatisfy(\.outcome.isDone) && mismatches.isEmpty && deviceCheck != .unanswered

  }

}
