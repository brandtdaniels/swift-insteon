import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// A device a ``DeviceLinkingCoordinator`` forgot after removing it from the network.
///
/// The network's registry no longer has its identity, its state in the network's snapshot is
/// gone, its ALL-Link database copy is forgotten, and the snapshot's copy of the modem's
/// ALL-Link database no longer holds records that name it.
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
  public var records: [AllLinkRecordResponse]

  /// Creates leftover records.
  ///
  /// - Parameters:
  ///   - address: The device whose database holds the records.
  ///   - device: The device as the registry knows it.
  ///   - records: The records that name the removed device.
  public init(address: InsteonAddress, device: RegisteredDevice?, records: [AllLinkRecordResponse]) {

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
  public var deviceDescription: DeviceDescription?

  /// The catalog's reset procedure, with its steps, notes and alternatives, or `nil` when the
  /// catalog doesn't have one for the device.
  public var procedure: DeviceLifecycle.Procedure?

  /// What a factory reset erases, if the catalog says. Empty when it doesn't.
  public var erases: Set<DeviceLifecycle.Erasure>

  /// Creates reset steps.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - deviceDescription: What the catalog says about the device.
  ///   - procedure: The catalog's reset procedure.
  ///   - erases: What a factory reset erases.
  public init(
    address: InsteonAddress,
    deviceDescription: DeviceDescription?,
    procedure: DeviceLifecycle.Procedure?,
    erases: Set<DeviceLifecycle.Erasure>
  ) {

    self.address = address
    self.deviceDescription = deviceDescription
    self.procedure = procedure
    self.erases = erases

  }

}

/// What a ``DeviceLinkingCoordinator`` did to remove a device from the network.
public struct DeviceRemovalResult: Sendable {

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

  /// The modem's records that named the device and were deleted directly, because it didn't
  /// answer and the caller asked for it. Empty otherwise.
  public var deletedModemRecords: [AllLinkRecord]

  /// The device the network forgot.
  public var forgotten: ForgottenDevice

  /// The records other devices still hold that name the device, or `nil` when they weren't
  /// looked for.
  public var leftoverRecords: LeftoverRecordScan?

  /// How to restore the device's factory settings, for a person to follow.
  public var factoryReset: FactoryResetSteps

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - removed: The links removed through the device.
  ///   - remainingLinks: The links the modem still has with the device.
  ///   - remoteUnlinkingFailure: Why the links couldn't be removed through the device.
  ///   - deletedModemRecords: The modem's records deleted directly.
  ///   - forgotten: The device the network forgot.
  ///   - leftoverRecords: The records other devices still hold that name the device.
  ///   - factoryReset: How to restore the device's factory settings.
  public init(
    removed: RemovedLinks,
    remainingLinks: [ModemLink]?,
    remoteUnlinkingFailure: (any Error)?,
    deletedModemRecords: [AllLinkRecord],
    forgotten: ForgottenDevice,
    leftoverRecords: LeftoverRecordScan?,
    factoryReset: FactoryResetSteps
  ) {

    self.removed = removed
    self.remainingLinks = remainingLinks
    self.remoteUnlinkingFailure = remoteUnlinkingFailure
    self.deletedModemRecords = deletedModemRecords
    self.forgotten = forgotten
    self.leftoverRecords = leftoverRecords
    self.factoryReset = factoryReset

  }

}
