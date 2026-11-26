import InsteonProtocol

extension AllLinkGroupReading {

  /// Pairs the records of databases that were read earlier, such as ones a backup holds, the way
  /// ``AllLinkGroupReader/read(devices:)`` pairs what it reads. It sends nothing.
  ///
  /// Only records in use count. A device in `unreadable` has no database in `devices`, so links
  /// to it are not reported as half links.
  ///
  /// - Parameters:
  ///   - modem: The modem's address.
  ///   - modemRecords: The records in the modem's database.
  ///   - devices: The records in each device's database, by the device's address.
  ///   - unreadable: The devices whose databases are not held.
  public init(modem: InsteonAddress, modemRecords: [AllLinkRecord], devices: [InsteonAddress: [AllLinkRecord]], unreadable: [InsteonAddress]) {

    var databases: [InsteonAddress: (endpoint: LinkEndpoint, records: [AllLinkRecord])] = [
      modem: (.modem, modemRecords.filter { $0.flags.contains(.inUse) })
    ]

    for (address, records) in devices where address != modem {

      databases[address] = (.device(address), records.filter { $0.flags.contains(.inUse) })

    }

    self = AllLinkGroupReader.pair(databases, modem: modem, unreadable: unreadable.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) })

  }

}
