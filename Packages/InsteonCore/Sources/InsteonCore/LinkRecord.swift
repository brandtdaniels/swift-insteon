import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// A record of an ALL-Link database, the modem's or a device's: the link it holds and its
/// three data bytes.
///
/// A controller record says the database's owner controls the group, and the other device
/// responds to it. A responder record says the owner responds to the other device's group.
///
/// ```swift
/// for record in try await network.allLinkDatabase(of: lamp).records where record.isInUse {
///   print(record.isController ? "controller" : "responder", record.group, record.address)
/// }
/// ```
public struct LinkRecord: Hashable, Sendable {

  /// Whether the database's owner controls the group, rather than responding to it.
  public var isController: Bool

  /// Whether the record holds a link. A record not in use is free, or it marks the end of a
  /// device's database.
  public var isInUse: Bool

  /// The group: the owner's own group in a controller record, and the other device's in a
  /// responder record.
  public var group: AllLinkGroupNumber

  /// The other device in the link.
  public var address: InsteonAddress

  /// The record's three data bytes, whose meaning depends on the device, such as a
  /// responder's on-level and ramp rate.
  public var data: [UInt8]

  /// Where the record is in a device's database, or `nil` for a record of the modem's.
  public var memoryAddress: UInt16?

  /// Creates a record.
  ///
  /// - Parameters:
  ///   - isController: Whether the owner controls the group.
  ///   - isInUse: Whether the record holds a link.
  ///   - group: The group.
  ///   - address: The other device in the link.
  ///   - data: The three data bytes.
  ///   - memoryAddress: Where the record is in a device's database, or `nil` for a record of
  ///     the modem's. Defaults to `nil`.
  public init(
    isController: Bool,
    isInUse: Bool,
    group: AllLinkGroupNumber,
    address: InsteonAddress,
    data: [UInt8],
    memoryAddress: UInt16? = nil
  ) {

    self.isController = isController
    self.isInUse = isInUse
    self.group = group
    self.address = address
    self.data = data
    self.memoryAddress = memoryAddress

  }

  /// The record a modem's ALL-Link database holds.
  init(_ record: AllLinkRecord) {

    self.init(
      isController: record.flags.contains(.controller),
      isInUse: record.flags.contains(.inUse),
      group: record.group,
      address: record.address,
      data: [record.data1, record.data2, record.data3]
    )

  }

  /// The record a device reported from its ALL-Link database, with its memory address.
  init(_ response: AllLinkRecordResponse) {

    self.init(
      isController: response.record.flags.contains(.controller),
      isInUse: response.record.flags.contains(.inUse),
      group: response.record.group,
      address: response.record.address,
      data: [response.record.data1, response.record.data2, response.record.data3],
      memoryAddress: response.address
    )

  }

  /// The protocol's record with the same link and data bytes, for the catalog to explain.
  var allLinkRecord: AllLinkRecord {

    var flags: AllLinkRecordFlags = []

    if isInUse {

      flags.insert(.inUse)

    }

    if isController {

      flags.insert(.controller)

    }

    return AllLinkRecord(
      flags: flags,
      group: group,
      address: address,
      data1: data.count > 0 ? data[0] : 0x00,
      data2: data.count > 1 ? data[1] : 0x00,
      data3: data.count > 2 ? data[2] : 0x00
    )

  }

}

/// A device's ALL-Link database, from ``DeviceNetwork/allLinkDatabase(of:beforeReading:)``:
/// its records and the delta it was read at.
public struct LinkDatabase: Hashable, Sendable {

  /// The delta the device reported when its database was read. A device changes its delta
  /// when its database changes.
  public var delta: UInt8

  /// The records, in the device's order, ending with the record that marks the end of the
  /// database.
  public var records: [LinkRecord]

  /// Creates a database.
  ///
  /// - Parameters:
  ///   - delta: The delta the database was read at.
  ///   - records: The records, in the device's order.
  public init(delta: UInt8, records: [LinkRecord]) {

    self.delta = delta
    self.records = records

  }

  /// The database a copy of the device's holds.
  init(_ copy: AllLinkDatabaseCopy) {

    self.init(delta: copy.delta, records: copy.records.map { (response: AllLinkRecordResponse) -> LinkRecord in LinkRecord(response) })

  }

}

extension DeviceDescription {

  /// What a record's data bytes mean for the device, as the Insteon device catalog gives
  /// them.
  ///
  /// - Parameter record: The record, from the device's ALL-Link database.
  /// - Returns: The explanation, or `nil` if the catalog doesn't describe the record's bytes.
  public func explain(_ record: LinkRecord) -> RecordDataExplanation? {

    explain(record.allLinkRecord, isController: record.isController)

  }

}
