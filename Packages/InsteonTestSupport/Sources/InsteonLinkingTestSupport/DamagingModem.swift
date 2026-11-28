import InsteonLinking
import InsteonModem
import InsteonProtocol

/// A modem that passes each call to another and damages the checksums of the single-record
/// reads a test lists, so a record can arrive damaged on one read and intact on the next.
///
/// Reads of a whole database pass through untouched.
public actor DamagingModem: LinkingModem {

  /// The modem each call goes to.
  public let base: any LinkingModem

  /// For each device and address, whether each coming read of the record arrives damaged,
  /// in order. A read past the list arrives as the base modem sends it.
  private var damagedReads: [InsteonAddress: [UInt16: [Bool]]] = [:]

  /// For each device and address, the error each coming read of the record throws, in order, or `nil` for a read
  /// that goes through. A read past the list goes through.
  private var failingReads: [InsteonAddress: [UInt16: [(any Error)?]]] = [:]

  /// A read the modem carries out, which ``setAfterRead(_:)`` can follow.
  public enum Read: Sendable {

    /// One record of a device's database, with the device and the record's address.
    case record(InsteonAddress, UInt16)

    /// A device's whole database.
    case database(InsteonAddress)

    /// The modem's records for a group and device.
    case group
  }

  /// For each device, the error each coming read of its whole database throws, in order, or `nil` for a read that
  /// goes through. A read past the list goes through.
  private var failingDatabaseReads: [InsteonAddress: [(any Error)?]] = [:]

  /// What runs after each read the modem carries out, if anything.
  private var afterRead: (@Sendable (Read) async -> Void)?

  /// Creates a modem that passes each call to `base`.
  ///
  /// - Parameter base: The modem each call goes to.
  public init(_ base: any LinkingModem) {

    self.base = base

  }

  /// Sets whether each coming read of a record arrives damaged, in order.
  ///
  /// - Parameters:
  ///   - reads: For each coming read, whether its checksum fails.
  ///   - address: The record's address.
  ///   - device: The device.
  public func setDamagedReads(_ reads: [Bool], at address: UInt16, of device: InsteonAddress) {

    damagedReads[device, default: [:]][address] = reads

  }

  /// Sets the error each coming read of a record throws, in order, such as a device that doesn't answer.
  ///
  /// - Parameters:
  ///   - errors: For each coming read, the error it throws, or `nil` to read.
  ///   - address: The record's address.
  ///   - device: The device.
  public func setFailingReads(_ errors: [(any Error)?], at address: UInt16, of device: InsteonAddress) {

    failingReads[device, default: [:]][address] = errors

  }

  /// Sets the error each coming read of a device's whole database throws, in order.
  public func setFailingDatabaseReads(_ errors: [(any Error)?], of device: InsteonAddress) {

    failingDatabaseReads[device] = errors

  }

  /// Reads through the base modem, failing the checksum when the next listed read says so.
  public func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    if var errors = failingReads[device]?[address], !errors.isEmpty {

      let error: (any Error)? = errors.removeFirst()

      failingReads[device]?[address] = errors

      if let error {

        throw error

      }

    }

    var response: AllLinkRecordResponse = try await base.readAllLinkRecord(of: device, at: address, timeout: timeout)

    if var reads = damagedReads[device]?[address], !reads.isEmpty {

      let isDamaged: Bool = reads.removeFirst()

      damagedReads[device]?[address] = reads
      response.hasIntactChecksum = response.hasIntactChecksum && !isDamaged

    }

    await afterRead?(.record(device, address))

    return response

  }

  /// Sends the command through the base modem.
  public func send(_ command: SerialCommand) async throws {

    try await base.send(command)

  }

  /// Asks the base modem.
  public func modemInfo() async throws -> ModemInfo {

    try await base.modemInfo()

  }

  /// Sends the message through the base modem.
  public func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    try await base.request(message, timeout: timeout)

  }

  /// Sends the message through the base modem.
  public func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    try await base.request(message, timeout: timeout)

  }

  /// Reads through the base modem.
  public func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    if var errors = failingDatabaseReads[device], !errors.isEmpty {

      let error: (any Error)? = errors.removeFirst()

      failingDatabaseReads[device] = errors

      if let error {

        throw error

      }

    }

    let records: [AllLinkRecordResponse] = try await base.readAllLinkDatabase(of: device, timeout: timeout)

    await afterRead?(.database(device))

    return records

  }

  /// Runs `hook` after each read of a record, a database or the modem's records for a group has been read and
  /// before it is returned, such as to cancel the task that asked, or stops running one.
  public func setAfterRead(_ hook: (@Sendable (Read) async -> Void)?) {

    afterRead = hook

  }

  /// Reads through the base modem.
  public func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    let records: [AllLinkRecord] = try await base.allLinkRecords(group: group, device: device)

    await afterRead?(.group)

    return records

  }

  /// Reads through the base modem.
  public func allLinkRecords() async throws -> [AllLinkRecord] {

    try await base.allLinkRecords()

  }

  /// The base modem's cleanup report.
  public func sendAllLinkCommand(group: AllLinkGroupNumber, command: Command, wait: AllLinkCleanupWait) async throws -> AllLinkCleanupReport {

    try await base.sendAllLinkCommand(group: group, command: command, wait: wait)

  }

  /// The base modem's replies.
  public func replies() async -> AsyncStream<ModemReply> {

    await base.replies()

  }

}
