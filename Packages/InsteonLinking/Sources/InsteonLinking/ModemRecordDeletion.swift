import InsteonModem
import InsteonProtocol

extension Unlinker {

  /// Deletes every record in the modem's own ALL-Link database that names a device, in every
  /// group and both roles, with Manage ALL-Link Record, without sending the device anything.
  ///
  /// It's for a device that's gone, such as one thrown away or a battery-powered device whose
  /// batteries are dead, so its links can't be removed with
  /// ``Unlinker/unlinkAllRemotely(_:unlinkingMode:timeout:willUnlink:)`` or its SET button.
  /// The device's own records of the links stay as they are; a device that comes back still
  /// holds them. The modem's delete matches a record's group and address, whatever its role,
  /// so one delete is sent for each record found.
  ///
  /// ```swift
  /// let deleted = try await Unlinker(modem: modem).deleteModemRecords(of: lostSensor)
  /// print("Deleted \(deleted.count) of the modem's records.")
  /// ```
  ///
  /// - Parameter device: The device whose records to delete.
  /// - Returns: The records deleted, in the modem's order, or an empty array if the modem had
  ///   none for the device.
  /// - Throws: The modem's errors. Records deleted before an error stay deleted; read the
  ///   modem's database again to see which are left.
  @discardableResult
  public func deleteModemRecords(of device: InsteonAddress) async throws -> [AllLinkRecord] {

    // The modem itself is asked, not a cache, so a stale copy can't leave a record behind.
    let all: [AllLinkRecord] = try await modem.allLinkRecords()
    let records: [AllLinkRecord] = all.filter { (record: AllLinkRecord) -> Bool in

      record.address == device && record.flags.contains(.inUse)

    }

    do {

      for record in records {

        let key = AllLinkRecord(flags: [], group: record.group, address: device)

        try await modem.send(.manageAllLinkRecord(action: .deleteFirst, record: key))

      }

    } catch {

      await cache?.invalidateModem()

      throw error

    }

    await cache?.invalidateModem()

    return records

  }

}
