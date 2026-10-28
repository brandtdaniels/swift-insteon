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

  /// Bit 0, which the i3 developer specifications name Fast Fail without describing it
  /// further. They say a device may change it at its own discretion.
  public static let fastFail = AllLinkRecordFlags(rawValue: 1 << 0)

  /// The record has been used before; when clear, the record marks the end of the database
  /// (bit 1).
  public static let usedBefore = AllLinkRecordFlags(rawValue: 1 << 1)

  /// The record's owner controls the linked device; when clear, it responds to it (bit 6).
  public static let controller = AllLinkRecordFlags(rawValue: 1 << 6)

  /// The record is in use; when clear, the record is available (bit 7).
  ///
  /// A deleted record keeps its other bits, so `0x62` is an erased record that had
  /// ``AllLinkRecordFlags/controller`` set and `0x22` one that didn't; `0x00` is a never-used
  /// record that ends the database.
  public static let inUse = AllLinkRecordFlags(rawValue: 1 << 7)

  /// Bits 3 and 4, from 0 through 3, the record's smart hop count.
  ///
  /// A record that's otherwise `0xE2` reads `0xEA`, `0xF2` or `0xFA` with smart hops set, and
  /// one that's otherwise `0xA2` reads `0xAA`, `0xB2` or `0xBA`.
  public var smartHops: UInt8 {

    (rawValue >> 3) & 0b11

  }

  /// The bits a device may change in a record on its own: ``AllLinkRecordFlags/fastFail`` and
  /// the smart hops bits 3 and 4.
  ///
  /// The i3 developer specifications say some flags "may be modified at the switch's
  /// discretion", and leave fast fail and the smart hop count out of their database checksum.
  public static let deviceMaintained = AllLinkRecordFlags(rawValue: 0b0001_1001)

}
