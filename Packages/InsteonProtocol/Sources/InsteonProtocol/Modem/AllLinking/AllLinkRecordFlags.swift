/// The flags byte of an ALL-Link database record.
///
/// A modem with a linear database copies ``AllLinkRecordFlags/inUse`` and
/// ``AllLinkRecordFlags/usedBefore`` from a record written with
/// ``AllLinkRecordAction/modifyFirstOrAdd``. A modem with a threaded database manages both bits
/// itself.
public struct AllLinkRecordFlags: OptionSet, Hashable, Sendable {

  /// The flags byte.
  public let rawValue: UInt8

  /// Creates record flags from a flags byte.
  ///
  /// - Parameter rawValue: The flags byte.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// The record has been used before; when clear, the record marks the end of the database
  /// (bit 1).
  public static let usedBefore = AllLinkRecordFlags(rawValue: 1 << 1)

  /// The record's owner controls the linked device; when clear, it responds to it (bit 6).
  public static let controller = AllLinkRecordFlags(rawValue: 1 << 6)

  /// The record is in use; when clear, the record is available (bit 7).
  public static let inUse = AllLinkRecordFlags(rawValue: 1 << 7)

}
