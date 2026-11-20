import Foundation
import InsteonProtocol
@testable import InsteonCore

/// Backups and records the transfer tests build, with invented addresses and data.
enum BackupExample {

  static let oldModem = InsteonAddress(0x11, 0x22, 0x33)
  static let newModem = InsteonAddress(0x77, 0x88, 0x99)
  static let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let plug = InsteonAddress(0x4D, 0x5E, 0x6F)
  static let sensor = InsteonAddress(0x0A, 0x0B, 0x0C)
  static let outlet = InsteonAddress(0x2A, 0x2B, 0x2C)
  static let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

  static func record(_ role: BackupRecordRole, group: UInt8, _ address: InsteonAddress, state: BackupRecordState = .inUse, data: [UInt8] = [0xFF, 0x1F, 0x01], memory: UInt16? = nil) -> BackupRecord {

    BackupRecord(state: state, role: role, group: group, address: address, data: data, memoryAddress: memory)

  }

  /// The end-of-database record that closes a device's records.
  static func end(_ memory: UInt16) -> BackupRecord {

    record(.responder, group: 0, InsteonAddress(0, 0, 0), state: .end, data: [0, 0, 0], memory: memory)

  }

  static func database(_ records: [BackupRecord], delta: UInt8 = 0x07) -> BackupDatabase {

    BackupDatabase(delta: delta, records: records)

  }

  /// A device that holds one responder record naming the old modem, whole.
  static func device(
    _ address: InsteonAddress,
    engine: BackupEngine? = .i2,
    records: [BackupRecord]? = nil,
    name: String? = nil
  ) -> BackupDevice {

    let held: [BackupRecord] = records ?? [record(.responder, group: 1, oldModem, memory: 0x0FFF), end(0x0FF7)]

    return BackupDevice(address: address, name: name, type: "Example Device", identity: BackupIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41), engine: engine, allLinkDatabase: database(held))

  }

  static func unreadable(_ address: InsteonAddress, _ reason: BackupUnreadableReason = .noAnswer) -> BackupDevice {

    BackupDevice(address: address, unreadable: BackupUnreadable(reason: reason))

  }

  /// A backup of the old modem with the devices, whose database is `modemRecords`: by default
  /// the old modem controls group 1 of each device.
  static func backup(_ devices: [BackupDevice], modemRecords: [BackupRecord]? = nil, source: BackupSourceKind = .modem) -> HomeBackup {

    let records: [BackupRecord] = modemRecords ?? devices.map { (device: BackupDevice) -> BackupRecord in record(.controller, group: 1, device.address) }

    return HomeBackup(createdAt: createdAt, source: source, modem: BackupModem(address: oldModem, allLinkDatabase: records), devices: devices)

  }

}
