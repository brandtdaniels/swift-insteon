/// A request for the modem to find, and optionally change or delete, a record in another
/// device's ALL-Link database, sent with ``SerialCommand/manageDeviceRecord(_:)``.
///
/// The modem reads the device's database itself, a record at a time, and reports the record
/// it finds with ``ModemReply/deviceRecordFound(address:record:)``. A record matches when its
/// ``AllLinkRecordFlags/controller`` bit, group and linked device are those of
/// ``DeviceRecordRequest/record``; a group of `0xFF` matches every group.
///
/// Insteon's command workbook annotates its examples as though a request with bit 6 clear
/// looked for a controller record, but its captured exchange shows such a request finding an
/// `0xA2` record, whose controller bit is clear. The request's bit 6 follows the captured
/// exchange: it's the record's own bit 6.
///
/// This is a later modem firmware command from Insteon's command workbook. The Insteon
/// Insteon Developer's Guide doesn't list it, and a modem without it NAKs the command.
///
/// ```swift
/// // Change the on-level and ramp rate of the switch's responder record for group 7.
/// let request = DeviceRecordRequest(
///   device: kitchenSwitch,
///   record: AllLinkRecord(flags: [.inUse], group: 0x07, address: modemAddress, data1: 0x7F, data2: 0x1C),
///   options: [.modify]
/// )
///
/// try await modem.send(.manageDeviceRecord(request))
/// ```
public struct DeviceRecordRequest: Hashable, Sendable {

  /// The device whose database the modem reads.
  public var device: InsteonAddress

  /// The record to match: its ``AllLinkRecordFlags/controller`` bit, its group and its linked
  /// device. Its data bytes are written by ``DeviceRecordOptions/modify``, and its third
  /// data byte is matched by ``DeviceRecordOptions/matchData3``.
  public var record: AllLinkRecord

  /// What to do with the record the modem finds.
  public var options: DeviceRecordOptions

  /// Creates a request.
  ///
  /// - Parameters:
  ///   - device: The device whose database the modem reads.
  ///   - record: The record to match.
  ///   - options: What to do with the record. Defaults to none: find it and report it.
  public init(device: InsteonAddress, record: AllLinkRecord, options: DeviceRecordOptions = []) {

    self.device = device
    self.record = record
    self.options = options

  }

  /// The request's flags byte: the options, with bit 6 set to match a record whose
  /// ``AllLinkRecordFlags/controller`` bit is set.
  var flags: UInt8 {

    options.rawValue | (record.flags.contains(.controller) ? 1 << 6 : 0)

  }

}

// MARK: - ByteEncodable

extension DeviceRecordRequest: ByteEncodable {

  /// The request's 11 bytes: the device, the flags, the group, the linked device and the three
  /// data bytes.
  public var bytes: [UInt8] {

    device.bytes + [flags, record.group.rawValue] + record.address.bytes + [record.data1, record.data2, record.data3]

  }

}

/// What ``SerialCommand/manageDeviceRecord(_:)`` does with the record it finds.
public struct DeviceRecordOptions: OptionSet, Hashable, Sendable {

  /// The flags' bits.
  public let rawValue: UInt8

  /// Creates options from their bits.
  ///
  /// - Parameter rawValue: The bits. Bits 4 through 7 aren't options and are dropped.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue & 0x0F

  }

  /// Matches the record's third data byte too (bit 0).
  public static let matchData3 = DeviceRecordOptions(rawValue: 1 << 0)

  /// Writes the request's data bytes into the record it finds (bit 1).
  public static let modify = DeviceRecordOptions(rawValue: 1 << 1)

  /// Deletes the record it finds (bit 2).
  public static let delete = DeviceRecordOptions(rawValue: 1 << 2)

  /// Starts the search at the record the last request found, to find the next match (bit 3).
  public static let continueFromLastFound = DeviceRecordOptions(rawValue: 1 << 3)

}
