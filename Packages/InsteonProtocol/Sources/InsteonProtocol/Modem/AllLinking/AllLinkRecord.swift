/// A record in an ALL-Link database, describing one link with another device.
///
/// The three data bytes depend on the device and the record's role. For a responder record
/// on a dimmer they are typically the on-level, the ramp rate and the button number.
///
/// In a modem's database, a controller record holds the linked device's category, subcategory
/// and firmware version, and a responder record holds the data set with
/// ``SerialCommand/setResponderLinkData(data1:data2:data3:)``.
public struct AllLinkRecord: Hashable, Sendable {

  /// Whether the record is in use, and whether it is a controller or responder record.
  public var flags: AllLinkRecordFlags

  /// The ALL-Link group the link belongs to.
  public var group: AllLinkGroup

  /// The address of the linked device.
  public var address: InsteonAddress

  /// The first byte of link data.
  public var data1: UInt8

  /// The second byte of link data.
  public var data2: UInt8

  /// The third byte of link data.
  public var data3: UInt8

  /// Creates a record.
  ///
  /// - Parameters:
  ///   - flags: The record's flags.
  ///   - group: The ALL-Link group.
  ///   - address: The address of the linked device.
  ///   - data1: The first byte of link data. Defaults to `0x00`.
  ///   - data2: The second byte of link data. Defaults to `0x00`.
  ///   - data3: The third byte of link data. Defaults to `0x00`.
  public init(
    flags: AllLinkRecordFlags,
    group: AllLinkGroup,
    address: InsteonAddress,
    data1: UInt8 = 0x00,
    data2: UInt8 = 0x00,
    data3: UInt8 = 0x00
  ) {

    self.flags = flags
    self.group = group
    self.address = address
    self.data1 = data1
    self.data2 = data2
    self.data3 = data3

  }

}

// MARK: - ByteEncodable

extension AllLinkRecord: ByteEncodable {

  /// The record's eight bytes: flags, group, address and the three data bytes.
  public var bytes: [UInt8] {

    [flags.rawValue, group.rawValue] + address.bytes + [data1, data2, data3]

  }

}
