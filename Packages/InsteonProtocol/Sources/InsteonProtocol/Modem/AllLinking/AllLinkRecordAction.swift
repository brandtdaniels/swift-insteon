/// What ``SerialCommand/manageAllLinkRecord(action:record:)`` does with a record.
///
/// Searches match a record's group and address, ignoring its flags.
public enum AllLinkRecordAction: UInt8, CaseIterable, Hashable, Sendable {

  /// Finds the first matching record (`0x00`). The modem NAKs if there is none.
  case findFirst = 0x00

  /// Finds the next matching record after the last one found (`0x01`).
  case findNext = 0x01

  /// Overwrites the first matching record, flags included, or adds the record (`0x20`).
  ///
  /// The modem copies the flags as given, so clearing ``AllLinkRecordFlags/inUse`` on the
  /// first record of a linear database makes the database appear empty.
  case modifyFirstOrAdd = 0x20

  /// Overwrites the first matching controller record, or adds the record as a controller
  /// record (`0x40`).
  case modifyFirstControllerOrAdd = 0x40

  /// Overwrites the first matching responder record, or adds the record as a responder
  /// record (`0x41`).
  case modifyFirstResponderOrAdd = 0x41

  /// Deletes the first matching record (`0x80`). The modem NAKs if there is none.
  case deleteFirst = 0x80

}
