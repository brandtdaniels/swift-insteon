extension SerialCommand {

  /// Manage ALL-Link Record that adds a record to the modem's database in its role, or
  /// updates the modem's first record of that role with the same group and address.
  ///
  /// - Parameter record: The record, whose ``AllLinkRecordFlags/controller`` flag gives its
  ///   role.
  /// - Returns: The command.
  package static func addAllLinkRecord(_ record: AllLinkRecord) -> SerialCommand {

    .manageAllLinkRecord(action: record.flags.contains(.controller) ? .modifyFirstControllerOrAdd : .modifyFirstResponderOrAdd, record: record)

  }

  /// Manage ALL-Link Record that deletes the modem's first record of a group that names an
  /// address, whatever its role.
  ///
  /// - Parameters:
  ///   - group: The record's group.
  ///   - address: The address the record names.
  /// - Returns: The command.
  package static func deleteFirstAllLinkRecord(group: AllLinkGroupNumber, address: InsteonAddress) -> SerialCommand {

    .manageAllLinkRecord(action: .deleteFirst, record: AllLinkRecord(flags: [], group: group, address: address))

  }

}
