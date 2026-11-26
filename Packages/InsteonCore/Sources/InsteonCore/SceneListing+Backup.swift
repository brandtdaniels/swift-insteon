import InsteonLinking
import InsteonProtocol

extension SceneListing {

  /// Lists the scenes of the ALL-Link databases a backup holds, the way ``init(_:)`` lists a
  /// reading, but from what was cached, sending nothing.
  ///
  /// A device the backup has no database for is in ``unreadable``, and a device its records name
  /// that the backup doesn't list is in ``unlisted``. A backup with no modem database, or with no
  /// modem at all, lists no scene and is marked ``isModemUnread``, since every scene is the modem's
  /// or a device's link to it.
  ///
  /// - Parameter backup: The backup.
  public init(_ backup: NetworkBackup) {

    guard let modem = backup.modem, let modemRecords = modem.allLinkDatabase else {

      self.init(scenes: [], unreadable: backup.devices.filter { $0.allLinkDatabase == nil }.map(\.address).sorted(by: Self.addressOrder), isModemUnread: true)

      return

    }

    var databases: [InsteonAddress: [AllLinkRecord]] = [:]
    var unreadable: [InsteonAddress] = []

    for device in backup.devices {

      if let database = device.allLinkDatabase {

        databases[device.address] = database.records.map(Self.record)

      } else {

        unreadable.append(device.address)

      }

    }

    self.init(AllLinkGroupReading(modem: modem.address, modemRecords: modemRecords.map(Self.record), devices: databases, unreadable: unreadable))

  }

  private static func record(_ record: BackupRecord) -> AllLinkRecord {

    let data: [UInt8] = Array((record.data + [0x00, 0x00, 0x00]).prefix(3))

    return AllLinkRecord(
      flags: record.isInUse ? (record.role == .controller ? [.inUse, .controller] : [.inUse]) : [],
      group: AllLinkGroupNumber(rawValue: record.group),
      address: record.address,
      data1: data[0],
      data2: data[1],
      data3: data[2]
    )

  }

  private static func addressOrder(_ lhs: InsteonAddress, _ rhs: InsteonAddress) -> Bool {

    lhs.bytes.lexicographicallyPrecedes(rhs.bytes)

  }

}
