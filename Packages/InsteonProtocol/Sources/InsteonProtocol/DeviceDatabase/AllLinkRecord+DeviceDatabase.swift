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
