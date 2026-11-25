import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A ``TransferWriting`` that reads and writes through a connected modem: the modem's own
/// ALL-Link database, and the devices' databases by their remote read and write commands.
///
/// A device's record is rewritten in place: the writer reads the slot and changes only the
/// address and the data bytes, so the flags a device maintains stay as they are. Only the
/// modem's records and the devices' records the plan names are touched.
public struct ModemTransferWriter: TransferWriting {

  private let modem: any LinkingModem
  private let engines: [InsteonAddress: BackupEngine]

  /// Creates a writer.
  ///
  /// - Parameters:
  ///   - modem: The connected new modem.
  ///   - plan: The plan it carries out, which says what engine each device runs.
  public init(modem: any LinkingModem, plan: TransferPlan) {

    self.modem = modem
    self.engines = Dictionary(plan.devices.map { ($0.address, $0.engine) }, uniquingKeysWith: { first, _ in first })

  }

  public func modemRecords() async throws -> [BackupRecord] {

    try await modem.allLinkRecords().filter { $0.flags.contains(.inUse) }.map { BackupRecord(LinkRecord($0)) }

  }

  public func deviceRecord(of device: InsteonAddress, at memoryAddress: UInt16) async throws -> BackupRecord? {

    let response: AllLinkRecordResponse = try await read(device, at: memoryAddress)
    var record: LinkRecord = LinkRecord(response.record)

    record.memoryAddress = memoryAddress

    return BackupRecord(record)

  }

  public func addToModem(_ record: BackupRecord) async throws {

    let flags: AllLinkRecordFlags = record.role == .controller ? [.inUse, .usedBefore, .controller] : [.inUse, .usedBefore]
    let stored: AllLinkRecord = AllLinkRecord(
      flags: flags,
      group: AllLinkGroupNumber(rawValue: record.group),
      address: record.address,
      data1: record.data[0],
      data2: record.data[1],
      data3: record.data[2]
    )

    try await modem.send(.addAllLinkRecord(stored))

  }

  public func removeFromModem(_ record: BackupRecord) async throws {

    try await modem.send(.deleteFirstAllLinkRecord(group: AllLinkGroupNumber(rawValue: record.group), address: record.address))

  }

  public func write(_ record: BackupRecord, to device: InsteonAddress) async throws {

    guard let memoryAddress = record.memoryAddress else { return }

    var stored: AllLinkRecord = try await read(device, at: memoryAddress).record

    stored.address = record.address
    stored.data1 = record.data[0]
    stored.data2 = record.data[1]
    stored.data3 = record.data[2]

    try await modem.writeAllLinkRecord(stored, at: memoryAddress, of: device, timeout: Modem.defaultExtendedRequestTimeout)

  }

  private func read(_ device: InsteonAddress, at memoryAddress: UInt16) async throws -> AllLinkRecordResponse {

    engines[device] == .i2cs
      ? try await modem.readAllLinkRecordCheckingIntegrity(of: device, at: memoryAddress, timeout: Modem.defaultExtendedRequestTimeout)
      : try await modem.readAllLinkRecord(of: device, at: memoryAddress, timeout: Modem.defaultExtendedRequestTimeout)

  }

}
