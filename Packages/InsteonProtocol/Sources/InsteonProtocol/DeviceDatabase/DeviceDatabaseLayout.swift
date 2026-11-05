/// Where a device keeps the records of its ALL-Link database.
///
/// A device's records sit from `0x0FFF` down to `0x0300`. Each record is 8 bytes, so their
/// addresses count down by 8 from `0x0FFF` to `0x0307`, the lowest. A linear database ends with a record that has never been used; adding a record past
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
