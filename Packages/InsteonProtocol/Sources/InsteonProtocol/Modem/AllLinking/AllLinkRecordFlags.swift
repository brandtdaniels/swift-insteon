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

  /// The device fails fast when a message to the record's device goes unanswered (bit 0), as
  /// i3 devices define it.
  ///
  /// The i3 developer specifications say the device may change it at its own discretion.
  public static let fastFail = AllLinkRecordFlags(rawValue: 1 << 0)

  /// The record has been used before; when clear, the record marks the end of the database
  /// (bit 1).
  public static let usedBefore = AllLinkRecordFlags(rawValue: 1 << 1)

  /// The record's owner controls the linked device; when clear, it responds to it (bit 6).
  public static let controller = AllLinkRecordFlags(rawValue: 1 << 6)

  /// The record is in use; when clear, the record is available (bit 7).
  ///
  /// A deleted record keeps its other bits, so `0x62` is an erased record that had
  /// ``AllLinkRecordFlags/controller`` set and `0x22` one that didn't, as Insteon's command
  /// workbook lists them; `0x00` is a never-used record that ends the database.
  public static let inUse = AllLinkRecordFlags(rawValue: 1 << 7)

  /// Bits 3 and 4, from 0 through 3, which Insteon's command workbook labels SmartHop.
  ///
  /// The workbook lists `0xEA`, `0xF2` and `0xFA` for a record that's otherwise `0xE2`, and
  /// `0xAA`, `0xB2` and `0xBA` for one that's otherwise `0xA2`, as all the smart hop settings,
  /// without saying more about what they mean.
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
