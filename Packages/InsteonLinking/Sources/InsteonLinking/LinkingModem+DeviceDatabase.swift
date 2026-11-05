import InsteonModem
import InsteonProtocol

// Writing and reading one record of a device's ALL-Link database.
extension LinkingModem {

  /// Writes a record into a slot of a device's database with Read/Write ALL-Link Database
  /// (`0x2F`), and waits for the device to acknowledge it.
  ///
  /// - Parameters:
  ///   - record: The record.
  ///   - address: The slot's address.
  ///   - device: The device.
  ///   - timeout: How long to wait for the device.
  /// - Throws: The modem's errors, such as `ModemError.deviceTimedOut` or
  ///   `ModemError.deviceRejected`.
  package func writeAllLinkRecord(_ record: AllLinkRecord, at address: UInt16, of device: InsteonAddress, timeout: Duration) async throws {

    _ = try await request(AllLinkDatabaseRequest.write(record, address: address).message(to: device), timeout: timeout)

  }

  /// Reads one record of a device's database and checks its checksum, reading it once more
  /// when the checksum fails, as an i2CS device's record damaged on the way does.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - address: The slot's address.
  ///   - timeout: How long to wait for the device.
  /// - Returns: The record, with an intact checksum.
  /// - Throws: `ModemError.deviceTimedOut` when the second read's checksum fails too, and the
  ///   modem's errors.
  package func readAllLinkRecordCheckingIntegrity(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    let first: AllLinkRecordResponse = try await readAllLinkRecord(of: device, at: address, timeout: timeout)

    guard !first.hasIntactChecksum else {

      return first

    }

    let second: AllLinkRecordResponse = try await readAllLinkRecord(of: device, at: address, timeout: timeout)

    guard second.hasIntactChecksum else {

      throw ModemError.deviceTimedOut(device)

    }

    return second

  }

  /// Whether a slot of a device's database reads back as `expected`, but for the flags a
  /// device may change on its own.
  ///
  /// - Parameters:
  ///   - expected: The record the slot should hold.
  ///   - address: The slot's address.
  ///   - device: The device.
  ///   - timeout: How long to wait for the device.
  ///   - checkingIntegrity: Whether the record is read with
  ///     ``LinkingModem/readAllLinkRecordCheckingIntegrity(of:at:timeout:)``, which reads a
  ///     record whose checksum fails once more, rather than read once whatever its checksum.
  /// - Returns: Whether the slot holds the record.
  /// - Throws: The errors of the read.
  package func slotHolds(_ expected: AllLinkRecord, at address: UInt16, of device: InsteonAddress, timeout: Duration, checkingIntegrity: Bool) async throws -> Bool {

    let current: AllLinkRecordResponse = checkingIntegrity
      ? try await readAllLinkRecordCheckingIntegrity(of: device, at: address, timeout: timeout)
      : try await readAllLinkRecord(of: device, at: address, timeout: timeout)

    return current.record.equalsIgnoringDeviceMaintained(expected)

  }

}
