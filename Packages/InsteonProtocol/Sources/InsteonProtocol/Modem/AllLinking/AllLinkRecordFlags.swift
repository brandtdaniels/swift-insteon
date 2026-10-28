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
  ///
  /// A deleted record keeps its other bits, so Insteon's command workbook shows an erased
  /// controller record as `0x62` and an erased responder record as `0x22`, and a never-used
  /// record at the end of the database as `0x00`.
  public static let inUse = AllLinkRecordFlags(rawValue: 1 << 7)

  /// The number of hops a device that keeps smart hops has learned it needs to reach the
  /// linked device, from 0 through 3 (bits 3 and 4).
  ///
  /// Insteon's command workbook shows these bits set on records of devices with later
  /// firmware, such as `0xF2`, `0xFA` and `0xEA` for a controller record that's otherwise
  /// `0xE2`. The Developer's Guide leaves them to the product.
  public var smartHops: UInt8 {

    (rawValue >> 3) & 0b11

  }

}
