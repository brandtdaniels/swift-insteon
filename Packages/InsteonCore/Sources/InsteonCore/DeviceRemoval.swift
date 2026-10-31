import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// A device a ``DeviceLinkingCoordinator`` forgot after removing it from the network.
///
/// The network's registry doesn't have its identity, its state in the network's snapshot is
/// gone, its ALL-Link database copy is forgotten, and the snapshot's copy of the modem's
/// ALL-Link database doesn't hold records that name it.
public struct ForgottenDevice: Hashable, Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The device as the registry knew it before it was forgotten, or `nil` if its identity
  /// wasn't known.
  public var device: RegisteredDevice?

  /// Creates a forgotten device.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - device: The device as the registry knew it.
  public init(address: InsteonAddress, device: RegisteredDevice?) {

    self.address = address
    self.device = device

  }

}

/// The records in one device's ALL-Link database that still name a removed device.
///
/// They're links the removed device made with this one, such as in a scene. They stay as they
/// are: the coordinator only reads other devices' databases.
public struct LeftoverRecords: Hashable, Sendable {

  /// The address of the device whose database holds the records.
  public var address: InsteonAddress

  /// The device whose database holds the records, as the registry knows it, or `nil` if its
  /// identity isn't known.
  public var device: RegisteredDevice?

  /// The records in use that name the removed device, in the database's order, each with its
  /// address in the database.
  public var records: [LinkRecord]

  /// Creates leftover records.
  ///
  /// - Parameters:
  ///   - address: The device whose database holds the records.
  ///   - device: The device as the registry knows it.
  ///   - records: The records that name the removed device.
  public init(address: InsteonAddress, device: RegisteredDevice?, records: [LinkRecord]) {

    self.address = address
    self.device = device
    self.records = records

  }

}

/// A device whose ALL-Link database couldn't be read while looking for records that name a
/// removed device.
public struct UnreadDatabase: Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The device as the registry knows it, or `nil` if its identity isn't known.
  public var device: RegisteredDevice?

  /// Why the database couldn't be read, such as `ModemError.deviceTimedOut`.
  public var reason: any Error

  /// Creates an unread database.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - device: The device as the registry knows it.
  ///   - reason: Why the database couldn't be read.
  public init(address: InsteonAddress, device: RegisteredDevice?, reason: any Error) {

    self.address = address
    self.device = device
    self.reason = reason

  }

}

/// What a ``DeviceLinkingCoordinator`` found in the ALL-Link databases of the other devices the
/// network knows, looking for records that still name a removed device.
///
/// Each database is the copy the network holds while the device reports the same delta, or
/// else read again. Nothing is written: removing these records from other devices' databases
/// is a database edit of its own.
public struct LeftoverRecordScan: Sendable {

  /// The removed device.
  public var removedDevice: InsteonAddress

  /// Each device whose database still names the removed device, in address order. Empty when
  /// no database read does.
  public var holders: [LeftoverRecords]

  /// Each device whose database couldn't be read, in address order, so it may name the
  /// removed device too.
  public var unread: [UnreadDatabase]

  /// Creates a scan.
  ///
  /// - Parameters:
  ///   - removedDevice: The removed device.
  ///   - holders: Each device whose database names the removed device.
  ///   - unread: Each device whose database couldn't be read.
  public init(removedDevice: InsteonAddress, holders: [LeftoverRecords], unread: [UnreadDatabase]) {

    self.removedDevice = removedDevice
    self.holders = holders
    self.unread = unread

  }

}

/// How to restore a removed device's factory settings, from the Insteon device catalog, for a
/// front end to show. The coordinator never resets a device itself.
public struct FactoryResetSteps: Hashable, Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// What the catalog says about the device, or `nil` if its identity isn't known.
  public var info: DeviceInfo?

  /// The catalog's reset steps and notes, or `nil` when the catalog doesn't have them for the
  /// device.
  public var procedure: Instructions?

  /// What a factory reset erases, if the catalog says. Empty when it doesn't.
  public var erases: Set<ResetErasure>

  /// Creates reset steps.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - info: What the catalog says about the device.
  ///   - procedure: The catalog's reset steps and notes.
  ///   - erases: What a factory reset erases.
  public init(
    address: InsteonAddress,
    info: DeviceInfo?,
    procedure: Instructions?,
    erases: Set<ResetErasure>
  ) {

    self.address = address
    self.info = info
    self.procedure = procedure
    self.erases = erases

  }

  /// Creates reset steps from the catalog's description and procedure.
  init(
    address: InsteonAddress,
    deviceDescription: DeviceDescription?,
    procedure: DeviceLifecycle.Procedure?,
    erases: Set<DeviceLifecycle.Erasure>
  ) {

    self.init(
      address: address,
      info: deviceDescription.map { (description: DeviceDescription) -> DeviceInfo in DeviceInfo(description) },
      procedure: procedure.map { (procedure: DeviceLifecycle.Procedure) -> Instructions in Instructions(procedure) },
      erases: Set(erases.map { (erasure: DeviceLifecycle.Erasure) -> ResetErasure in ResetErasure(erasure) })
    )

  }

  /// The catalog's description of the device.
  var deviceDescription: DeviceDescription? {

    info?.catalogDescription

  }

}

/// Why a ``DeviceLinkingCoordinator`` deletes the modem's records for a removed device
/// directly, once the caller said the device is gone.
public enum ModemRecordDeletionReason: Sendable {

  /// The device didn't answer, such as one whose batteries are dead.
  case noAnswer

  /// The device's engine can't be linked or unlinked remotely, as an i1 device can't.
  case remoteLinkingUnsupported

  /// Removing a link through the device failed for another reason.
  case remoteUnlinkingFailed(any Error)

  /// The links were removed through the device, but the modem still has these.
  case linksLeft([ModemLink])

  /// The links were removed through the device, but the modem's ALL-Link database couldn't be
  /// read to check that none are left.
  case modemLinksUnreadable(any Error)

}

/// Why a ``DeviceLinkingCoordinator`` kept a device it was asked to remove, so the network
/// still knows it.
///
/// The device is forgotten only once the modem's ALL-Link database, read again, has no links
/// with it.
public enum DeviceKeptReason: Sendable {

  /// The modem still has these links with the device, each role and group once, in the
  /// modem's order.
  case linksRemain([ModemLink])

  /// The modem's ALL-Link database couldn't be read again, so whether links are left isn't
  /// known.
  case modemLinksUnreadable(any Error)

  /// The modem rejected deleting one of its records for the device, or failed partway; the
  /// records deleted before that stay deleted.
  case modemRecordsNotDeleted(any Error)

}

/// What a ``DeviceLinkingCoordinator`` did to remove a device from the network.
///
/// A device whose links with the modem are all gone is forgotten, and the result has the
/// catalog's factory reset steps. A device with links left is kept:
/// ``DeviceRemovalResult/keptBecause`` says why, and there's no
/// ``DeviceRemovalResult/forgotten`` device, scan or reset steps.
public struct DeviceRemovalResult: Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The links removed through the device, without its SET button. Empty when the modem had
  /// none with it, or when the device didn't answer and the modem's records were deleted
  /// instead.
  public var removed: RemovedLinks

  /// The links the modem still has with the device after the removal, or `nil` if its
  /// database couldn't be read again.
  public var remainingLinks: [ModemLink]?

  /// Why the links couldn't be removed through the device, when the modem's records that name
  /// it were deleted directly instead, or `nil` when they weren't.
  public var remoteUnlinkingFailure: (any Error)?

  /// The modem's records that named the device and were deleted directly, because the caller
  /// said it's gone. Empty otherwise.
  public var deletedModemRecords: [LinkRecord]

  /// The device the network forgot, or `nil` when it was kept.
  public var forgotten: ForgottenDevice?

  /// Why the device was kept, or `nil` when it was forgotten.
  public var keptBecause: DeviceKeptReason?

  /// The records other devices still hold that name the device, or `nil` when they weren't
  /// looked for or the device was kept.
  public var leftoverRecords: LeftoverRecordScan?

  /// How to restore the device's factory settings, for a person to follow, or `nil` when the
  /// device was kept.
  public var factoryReset: FactoryResetSteps?

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - removed: The links removed through the device.
  ///   - remainingLinks: The links the modem still has with the device.
  ///   - remoteUnlinkingFailure: Why the links couldn't be removed through the device.
  ///   - deletedModemRecords: The modem's records deleted directly.
  ///   - forgotten: The device the network forgot, or `nil` when it was kept.
  ///   - keptBecause: Why the device was kept, or `nil` when it was forgotten.
  ///   - leftoverRecords: The records other devices still hold that name the device.
  ///   - factoryReset: How to restore the device's factory settings.
  public init(
    address: InsteonAddress,
    removed: RemovedLinks,
    remainingLinks: [ModemLink]?,
    remoteUnlinkingFailure: (any Error)?,
    deletedModemRecords: [LinkRecord],
    forgotten: ForgottenDevice?,
    keptBecause: DeviceKeptReason?,
    leftoverRecords: LeftoverRecordScan?,
    factoryReset: FactoryResetSteps?
  ) {

    self.address = address
    self.removed = removed
    self.remainingLinks = remainingLinks
    self.remoteUnlinkingFailure = remoteUnlinkingFailure
    self.deletedModemRecords = deletedModemRecords
    self.forgotten = forgotten
    self.keptBecause = keptBecause
    self.leftoverRecords = leftoverRecords
    self.factoryReset = factoryReset

  }

}
