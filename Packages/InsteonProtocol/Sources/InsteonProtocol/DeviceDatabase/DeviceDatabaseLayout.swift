/// Where a device keeps the records of its ALL-Link database.
///
/// Insteon's Data Base Format sheet places a device's records from `0x0FFF` down to `0x0300`.
/// Each record is 8 bytes, so their addresses count down by 8 from `0x0FFF` to `0x0307`, the
/// lowest. A linear database ends with a record that has never been used; adding a record past
/// the last one in use writes the record below the end as the new end first, then the record
/// into the old end's slot.
package enum DeviceDatabaseLayout {

  /// The address of the first record: `0x0FFF`.
  package static let firstRecordAddress: UInt16 = 0x0FFF

  /// The address of the lowest record: `0x0307`.
  package static let lowestRecordAddress: UInt16 = 0x0307

  /// How many bytes a record takes, and how far apart two records' addresses are: 8.
  package static let recordLength: UInt16 = 8

  /// The address of the record just below the one at `address`.
  ///
  /// - Parameter address: A record's address.
  /// - Returns: The address 8 below, or `nil` when `address` is the lowest record's.
  package static func address(below address: UInt16) -> UInt16? {

    address >= lowestRecordAddress + recordLength ? address - recordLength : nil

  }

  /// How many records fit below the one at `address`.
  ///
  /// - Parameter address: A record's address.
  /// - Returns: The number of record addresses below it, down to the lowest.
  package static func recordCount(below address: UInt16) -> Int {

    address >= lowestRecordAddress + recordLength ? Int((address - lowestRecordAddress) / recordLength) : 0

  }

}

extension AllLinkRecordFlags {

  /// The flags of a record in use that a link writes: `0xE2` for a controller record and
  /// `0xA2` for a responder record, which also set the product-dependent bit 5.
  ///
  /// - Parameter isController: Whether the record is a controller record.
  /// - Returns: The flags.
  package static func linked(isController: Bool) -> AllLinkRecordFlags {

    AllLinkRecordFlags(rawValue: isController ? 0xE2 : 0xA2)

  }

}

extension AllLinkRecord {

  /// A record that has never been used, which marks the end of a device's database.
  package static let endOfDatabase = AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00))

  /// Whether the record is the same as `other` but for the flags a device may change on its
  /// own, ``AllLinkRecordFlags/deviceMaintained``, such as its smart hop count.
  ///
  /// - Parameter other: The record to compare with.
  /// - Returns: Whether the two match.
  package func equalsIgnoringDeviceMaintained(_ other: AllLinkRecord) -> Bool {

    var record = self, other = other
    record.flags.subtract(.deviceMaintained)
    other.flags.subtract(.deviceMaintained)

    return record == other

  }

}

extension AllLinkRecordResponse {

  /// Whether the record's slot can take a record: one used before and not in use, so
  /// writing it doesn't move the end of the database.
  package var isReusable: Bool {

    !isEndOfDatabase && !record.flags.contains(.inUse)

  }

}
